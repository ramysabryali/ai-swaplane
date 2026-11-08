import AppKit
import Adapters
import SwaplaneCore
import SwiftUI
import SwitchEngine
import Usage
import Vault

private final class NullKeychain: KeychainClient, @unchecked Sendable {
    func exists(service: String, account: String?) throws -> Bool { false }
    func read(service: String, account: String?) throws -> Data? { nil }
    func write(service: String, account: String?, data: Data) throws {}
    func delete(service: String, account: String?) throws {}
}

/// Developer aid: `SwaplaneApp --snapshot <dir>` renders the panel with synthetic data to PNGs
/// (no real accounts, no Keychain). Used to check the UI without driving the screen.
@MainActor
public enum SnapshotRenderer {
    public static func run(into dir: String) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("swaplane-snap-\(UUID().uuidString)")
        let paths = Paths(home: home)
        let kc = NullKeychain()
        let vault = Vault(paths: paths, keychain: kc)
        let engine = SwitchEngine(paths: paths, vault: vault, adapters: [], processes: AppKitProcessController())
        let model = AppModel(engine: engine, vault: vault, usage: UsageService(paths: paths, keychain: kc))
        model.snapshotMode = true
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let variants: [(String, String, Bool)] = [
            ("multi-dark", "multi", true), ("multi-light", "multi", false), ("one-dark", "one", true),
            ("empty-dark", "empty", true), ("welcome-light", "welcome", false), ("many-dark", "many", true),
        ]
        for (name, scenario, dark) in variants {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            model.seedForSnapshot(scenario)
            let view = PanelView(model: model).environment(\.colorScheme, dark ? .dark : .light)
                .padding(24).background(dark ? Color.black : Color(white: 0.85))
            let r = ImageRenderer(content: view)
            r.scale = 2
            guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                let png = rep.representation(using: .png, properties: [:])
            else { continue }
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        // Menu bar icon samples.
        let samples: [(Double, Double)] = [(10, 5), (62, 35), (85, 40), (97, 90)]
        let w = 36 * samples.count + 40
        let bar = HStack(spacing: 16) {
            ForEach(Array(samples.enumerated()), id: \.offset) { _, s in
                Image(nsImage: MenuBarIcon.image(primary: Palette.ns("blue"), secondary: Palette.ns("green"), session: s.0, weekly: s.1))
            }
        }.padding(10).frame(width: CGFloat(w)).background(Color(white: 0.2)).environment(\.colorScheme, .dark)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let r = ImageRenderer(content: bar); r.scale = 4
        if let tiff = r.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        { try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("menubar.png")) }
        composite(model: model, dark: true, into: dir)
        composite(model: model, dark: false, into: dir)
    }

    /// Developer aid: renders the first-run and new-account screens to PNGs (synthetic data).
    public static func runFlows(into dir: String) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("swaplane-snap-\(UUID().uuidString)")
        let paths = Paths(home: home)
        let kc = NullKeychain()
        let vault = Vault(paths: paths, keychain: kc)
        let engine = SwitchEngine(paths: paths, vault: vault, adapters: [], processes: AppKitProcessController())
        let model = AppModel(engine: engine, vault: vault, usage: UsageService(paths: paths, keychain: kc))
        model.snapshotMode = true
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func write<V: View>(_ name: String, _ v: V) {
            NSApp.appearance = NSAppearance(named: .darkAqua)
            let r = ImageRenderer(content: v.environment(\.colorScheme, .dark).background(Color(white: 0.16)))
            r.scale = 2
            if let tiff = r.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                let png = rep.representation(using: .png, properties: [:])
            { try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")) }
        }
        model.seedForSnapshot("detected")
        write("panel-detected", PanelView(model: model).padding(24))
        model.seedForSnapshot("empty")
        for i in 0..<5 { write("onboarding-\(i + 1)-empty", OnboardingView(model: model, page: i) {}) }
        model.seedKeychain(.denied)
        write("onboarding-2-denied", OnboardingView(model: model, page: 1) {})
        model.seedKeychain(nil)
        model.seedForSnapshot("welcome")
        write("onboarding-3-found", OnboardingView(model: model, page: 2, detecting: false) {})
        model.seedForSnapshot("detected")
        model.newAccount = NewAccountFlow(phase: .intro)
        write("new-1-intro", NewAccountView(model: model) {})
        model.seedForSnapshot("one")
        model.newAccount = NewAccountFlow(phase: .signIn)
        write("new-2-signin", NewAccountView(model: model) {})
        model.seedForSnapshot("found")
        model.newAccount = NewAccountFlow(phase: .signIn)
        write("new-3-found", NewAccountView(model: model) {})
    }

    /// A menu bar strip with the icon and the open panel underneath, for the README.
    static func composite(model: AppModel, dark: Bool, into dir: String) {
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        model.seedForSnapshot("multi")
        model.toast = nil
        let icon = MenuBarIcon.image(primary: Palette.ns("blue"), secondary: Palette.ns("green"), session: 18, weekly: 81)
        let barFg: Color = dark ? .white : .black
        let wall = dark
            ? LinearGradient(colors: [Color(red: 0.10, green: 0.14, blue: 0.24), Color(red: 0.05, green: 0.07, blue: 0.14)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(red: 0.86, green: 0.89, blue: 0.95), Color(red: 0.74, green: 0.80, blue: 0.90)], startPoint: .top, endPoint: .bottom)
        let view = ZStack(alignment: .topTrailing) {
            Rectangle().fill(wall)
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "wifi").font(.system(size: 12))
                    Image(systemName: "magnifyingglass").font(.system(size: 12))
                    Image(nsImage: icon).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(barFg.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
                    Text("Fri 9:41 AM").font(.system(size: 13))
                }
                .foregroundStyle(barFg.opacity(0.9))
                .padding(.horizontal, 16).frame(height: 28)
                .background(dark ? Color.black.opacity(0.35) : Color.white.opacity(0.5))
                PanelView(model: model)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .shadow(color: .black.opacity(dark ? 0.55 : 0.25), radius: 22, y: 10)
                    .padding(.trailing, 24)
            }
        }
        .frame(width: 560, height: 700)
        let r = ImageRenderer(content: view)
        r.scale = 2
        if let tiff = r.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        { try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("menubar-\(dark ? "dark" : "light").png")) }
    }
}
