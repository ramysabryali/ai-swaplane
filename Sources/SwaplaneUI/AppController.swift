import AppKit
import Adapters
import SwaplaneCore
import SwiftUI
import SwitchEngine
import Vault

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model: AppModel
    init(model: AppModel) { self.model = model }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Swaplane"
            w.contentViewController = NSHostingController(rootView: MainWindowView(model: model))
            w.isReleasedWhenClosed = false
            w.delegate = self
            if !w.setFrameUsingName("SwaplaneMain") { w.center() }
            w.setFrameAutosaveName("SwaplaneMain")
            window = w
        }
        ensureOnScreen()
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// If the display the window was on is gone, bring it back to the main screen.
    func ensureOnScreen() {
        guard let w = window else { return }
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(w.frame) }) {
            if let main = NSScreen.main {
                var f = w.frame
                f.origin = NSPoint(x: main.visibleFrame.midX - f.width / 2, y: main.visibleFrame.midY - f.height / 2)
                w.setFrame(f, display: true)
            } else { w.center() }
        }
    }

    func windowWillClose(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }
}

@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let model: AppModel
    private let main: MainWindowController

    init(model: AppModel, main: MainWindowController) {
        self.model = model
        self.main = main
        super.init()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model))
        if let b = item.button {
            b.image = NSImage(systemSymbolName: "arrow.left.arrow.right.circle", accessibilityDescription: "Swaplane")
            b.image?.isTemplate = true
            b.target = self
            b.action = #selector(clicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        model.onChange = { [weak self] in self?.refreshAccessibility() }
        // Displays added/removed: close the popover and make sure the window is still reachable.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.popover.performClose(nil)
                self?.main.ensureOnScreen()
            }
        }
    }

    private func refreshAccessibility() {
        let names = Tool.allCases.compactMap { t in model.activeProfile(for: t).map { "\(t.displayName): \($0.label)" } }
        let text = names.isEmpty ? "Swaplane" : "Swaplane — " + names.joined(separator: ", ")
        item.button?.toolTip = text
        item.button?.setAccessibilityLabel(text)
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.option) == true {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Swaplane…", action: #selector(openMain), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Swaplane", action: #selector(quit), keyEquivalent: "q").target = self
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
            return
        }
        if popover.isShown { popover.performClose(nil) }
        else {
            // NSPopover positions itself on the screen that owns the status item button and clamps to its visible frame.
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func openMain() { popover.performClose(nil); main.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: StatusItemController?
    private var main: MainWindowController?
    private var model: AppModel?

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let paths = Paths()
        let keychain = SystemKeychain()
        let vault = Vault(paths: paths, keychain: keychain)
        let engine = SwitchEngine(
            paths: paths, vault: vault,
            adapters: [ClaudeCodeAdapter(paths: paths, keychain: keychain), ClaudeDesktopAdapter(paths: paths)],
            processes: AppKitProcessController())
        let model = AppModel(engine: engine, vault: vault)
        let main = MainWindowController(model: model)
        model.onOpenMainWindow = { [weak main] in main?.show() }
        model.onQuit = { NSApp.terminate(nil) }
        self.model = model
        self.main = main
        self.status = StatusItemController(model: model, main: main)

        Task {
            _ = await engine.recoverIfNeeded()
            await model.reload()
            if model.profiles.isEmpty { model.showWizard = true; main.show() }
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
