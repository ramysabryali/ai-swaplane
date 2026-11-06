import AppKit
import Adapters
import SwaplaneCore
import SwiftUI
import SwitchEngine
import Usage
import Vault

/// Borderless floating panel that can take key focus (for Esc and keyboard hold).
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Settings window and the small add/re-authenticate window.
@MainActor
final class WindowsController: NSObject, NSWindowDelegate {
    private var settings: NSWindow?
    private var wizard: NSWindow?
    private let model: AppModel
    init(model: AppModel) { self.model = model }

    func showSettings() {
        if settings == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "AI Swaplane Settings"
            w.contentViewController = NSHostingController(rootView: SettingsView(model: model))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            settings = w
        }
        present(settings)
    }

    func showWizard() {
        let hosting = NSHostingController(rootView: ImportWizardView(model: model) { [weak self] in self?.closeWizard() })
        if wizard == nil {
            let w = NSWindow(contentViewController: hosting)
            w.styleMask = [.titled, .closable]
            w.title = "AI Swaplane"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            wizard = w
        } else { wizard?.contentViewController = hosting }
        present(wizard)
    }

    func closeWizard() { model.showWizard = false; wizard?.close() }

    private func present(_ w: NSWindow?) {
        guard let w else { return }
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(w.frame) }) { w.center() }
        NSApp.setActivationPolicy(.regular)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === wizard { model.pendingEmptyTool = nil; model.reauthProfile = nil; model.showWizard = false }
        DispatchQueue.main.async { [weak self] in
            let open = [self?.settings, self?.wizard].compactMap { $0 }.contains { $0.isVisible }
            if !open { NSApp.setActivationPolicy(.accessory) }
        }
    }

    func ensureOnScreen() { for w in [settings, wizard].compactMap({ $0 }) where !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(w.frame) }) { w.center() } }
}

@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: KeyPanel
    private let host: NSHostingController<PanelView>
    private let model: AppModel
    private let windows: WindowsController
    private var monitors: [Any] = []
    private var sizeObs: NSKeyValueObservation?

    init(model: AppModel, windows: WindowsController) {
        self.model = model
        self.windows = windows
        host = NSHostingController(rootView: PanelView(model: model))
        host.sizingOptions = [.preferredContentSize]
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        panel.contentViewController = host
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.onCancel = { [weak self] in self?.close() }
        sizeObs = host.observe(\.preferredContentSize, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.resize() }
        }
        if let b = item.button {
            b.target = self
            b.action = #selector(clicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        model.onChange = { [weak self] in self?.refreshIcon() }
        model.onClosePanel = { [weak self] in self?.close() }
        refreshIcon()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close(); self?.windows.ensureOnScreen() }
        }
    }

    // MARK: Icon

    private func refreshIcon() {
        let code = model.activeAccount(for: .claudeCode)
        let desk = model.activeAccount(for: .claudeDesktop)
        let primary = (code ?? desk).map { Palette.ns($0.group.colorName) }
        let second: NSColor? = (code != nil && desk != nil && code?.id != desk?.id) ? Palette.ns(desk!.group.colorName) : nil
        let snap = (code ?? desk).flatMap { model.usage[$0.id] }
        item.button?.image = MenuBarIcon.image(primary: primary, secondary: second, session: snap?.session?.percent, weekly: snap?.weekly?.percent)
        let names = Tool.allCases.compactMap { t in model.activeAccount(for: t).map { "\(t.shortName): \($0.group.label)" } }
        var text = names.isEmpty ? "AI Swaplane" : "AI Swaplane — " + names.joined(separator: ", ")
        if let s = snap?.session { text += ", session \(Int(s.percent.rounded())) percent" }
        if let w = snap?.weekly { text += ", weekly \(Int(w.percent.rounded())) percent" }
        item.button?.toolTip = text
        item.button?.setAccessibilityLabel(text)
    }

    // MARK: Panel

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.option) == true {
            close()
            let menu = NSMenu()
            menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit AI Swaplane", action: #selector(quit), keyEquivalent: "q").target = self
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
            return
        }
        // Click opens; a click while open does nothing. Outside clicks close (see monitors).
        if !panel.isVisible { open() }
    }

    private func open() {
        NSApp.appearance = model.appearance.nsAppearance
        resize()
        // Show without taking key focus so the frontmost app's window stays as it was.
        panel.orderFrontRegardless()
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated {
                    // A click on our own status item is handled by `clicked` (does nothing while open).
                    guard let self, !self.isOverStatusItem(NSEvent.mouseLocation) else { return }
                    self.close()
                }
            } as Any,
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
                MainActor.assumeIsolated {
                    // Clicking the status item toggles; clicks elsewhere in another window close.
                    if let self, e.window !== self.panel, e.window !== self.item.button?.window { self.close() }
                }
                return e
            } as Any,
        ]
    }

    private func isOverStatusItem(_ p: NSPoint) -> Bool {
        guard let f = item.button?.window?.frame else { return false }
        return f.insetBy(dx: -2, dy: -2).contains(p)
    }

    private func close() {
        panel.orderOut(nil)
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
    }

    /// Anchors under the status item on the screen that owns it, clamped to that screen's visible frame.
    private func resize() {
        guard let button = item.button, let bw = button.window else { return }
        let size = host.preferredContentSize
        guard size.width > 0, size.height > 0 else { return }
        let screen = bw.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let vis = screen.visibleFrame
        let anchor = bw.frame
        let h = min(size.height, vis.height - 12)
        var x = anchor.midX - size.width / 2
        x = max(vis.minX + 8, min(x, vis.maxX - size.width - 8))
        let y = max(vis.minY + 8, anchor.minY - 6 - h)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: h), display: true)
    }

    @objc private func openSettings() { windows.showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: StatusItemController?
    private var windows: WindowsController?
    private var model: AppModel?
    private var timer: Timer?

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let paths = Paths()
        let keychain = SystemKeychain()
        let vault = Vault(paths: paths, keychain: keychain)
        let engine = SwitchEngine(
            paths: paths, vault: vault,
            adapters: [ClaudeCodeAdapter(paths: paths, keychain: keychain), ClaudeDesktopAdapter(paths: paths)],
            processes: AppKitProcessController())
        let usage = UsageService(paths: paths, keychain: keychain)
        let model = AppModel(engine: engine, vault: vault, usage: usage)
        NSApp.appearance = model.appearance.nsAppearance
        AppIconArt.installDockIcon()
        let windows = WindowsController(model: model)
        model.onOpenSettings = { [weak windows] in windows?.showSettings() }
        model.onOpenWizard = { [weak windows] in windows?.showWizard() }
        model.onQuit = { NSApp.terminate(nil) }
        self.model = model
        self.windows = windows
        self.status = StatusItemController(model: model, windows: windows)

        Task {
            _ = await engine.recoverIfNeeded()
            await model.reload()
            await model.refreshUsage()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak model] _ in
            Task { @MainActor in await model?.reload(); await model?.refreshUsage() }
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
