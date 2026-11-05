import Foundation
import SwaplaneCore

/// Per-tool knowledge: where state lives, how to read identity, capture and apply it.
/// Adapters never stop/start processes themselves — the SwitchEngine does, using `processBundleID`.
public protocol ToolAdapter: Sendable {
    var tool: Tool { get }
    /// Bundle ID of the desktop app that must be quit while state is swapped (nil for CLIs).
    var processBundleID: String? { get }
    func probe() async -> ToolProbe
    /// Reads the live signed-in identity without side effects; nil if signed out.
    func detectCurrentIdentity() async throws -> DetectedIdentity?
    func capture() async throws -> StateBundle
    /// Makes `bundle` the live state. Called only inside a SwitchEngine transaction.
    func apply(_ bundle: StateBundle) async throws
    /// Puts the tool into a signed-out state so the user can sign in with another account.
    func prepareEmpty() async throws
    /// Confirms the live state matches the profile that was just applied.
    func verify(expectedIdentityKey: String?) async throws
}

enum JSONFile {
    static func readObject(_ url: URL) throws -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SwaplaneError.io("unexpected JSON shape in \(url.lastPathComponent)")
        }
        return obj
    }

    static func write(_ obj: [String: Any], to url: URL) throws {
        let mode = FileUtil.posixMode(of: url) ?? 0o600
        let data = try JSONSerialization.data(
            withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileUtil.atomicWrite(data, to: url, mode: mode)
    }
}
