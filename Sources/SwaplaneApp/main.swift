import AppKit
import SwaplaneUI

let app = NSApplication.shared
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated { SnapshotRenderer.run(into: CommandLine.arguments[i + 1]) }
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar app; Dock icon only while a window is open
app.run()
