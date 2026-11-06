import AppKit
import Foundation

/// Starts/stops desktop apps. Injectable so engine tests never touch real apps.
public protocol ProcessController: Sendable {
    func isRunning(bundleID: String) async -> Bool
    /// Graceful quit. Returns true if the app is no longer running within `timeout`.
    func quit(bundleID: String, timeout: TimeInterval) async -> Bool
    func launch(bundleID: String) async throws
}

public struct AppKitProcessController: ProcessController {
    public init() {}

    @MainActor private func running(_ id: String) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: id)
    }

    public func isRunning(bundleID: String) async -> Bool {
        await MainActor.run { !running(bundleID).isEmpty }
    }

    public func quit(bundleID: String, timeout: TimeInterval) async -> Bool {
        await MainActor.run { running(bundleID).forEach { _ = $0.terminate() } }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await !isRunning(bundleID: bundleID) { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return await !isRunning(bundleID: bundleID)
    }

    public func launch(bundleID: String) async throws {
        guard let url = await MainActor.run(body: {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        }) else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: cfg)
    }
}
