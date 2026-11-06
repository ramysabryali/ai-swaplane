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
    }
}
