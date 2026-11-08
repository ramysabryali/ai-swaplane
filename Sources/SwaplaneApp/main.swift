import AppKit
import SwaplaneUI

let app = NSApplication.shared
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated { SnapshotRenderer.run(into: CommandLine.arguments[i + 1]) }
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--snapshot-flows"), CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated { SnapshotRenderer.runFlows(into: CommandLine.arguments[i + 1]) }
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--render-icon"), CommandLine.arguments.count > i + 1 {
    MainActor.assumeIsolated { AppIconArt.writeAssets(to: CommandLine.arguments[i + 1]) }
    exit(0)
}
if CommandLine.arguments.contains("--test-notification") {
    MainActor.assumeIsolated { Reminders.sendTest() }
    RunLoop.main.run(until: Date().addingTimeInterval(8))
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar app; Dock icon only while a window is open
app.run()
