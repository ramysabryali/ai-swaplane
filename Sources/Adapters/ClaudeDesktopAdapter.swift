import Foundation
import SwaplaneCore

enum ClaudeDesktopConstants {
    // VERIFIED: 2026-11-05 (app 4.16336.0) — see docs/SPIKE-0-FINDINGS.md
    static let bundleID = "com.anthropic.claudefordesktop"
    static let verifiedVersions: Set<String> = ["4.16336.0"]
    static let appPaths = ["/Applications/Claude.app"]
    /// Top-level items inside the Electron user-data dir that hold auth/UI state.
    /// The data dir is ~15 GB (vm_bundles, caches) so this MUST be an allowlist.
    /// NEVER include the Keychain "Claude Safe Storage" key — it is shared and must not be touched.
    static let allowlist: [String] = [
        "Cookies", "Cookies-journal", "Local Storage", "Session Storage", "IndexedDB",
        "Partitions", "Network Persistent State", "Preferences", "Local State", "config.json",
        "Trust Tokens", "Trust Tokens-journal", "SharedStorage", "WebStorage",
        "ant-did", "ant-device-registry.json", "Service Worker",
    ]
    static let configFile = "config.json"
    static let accountKey = "lastKnownAccountUuid"
}

/// Claude Desktop (Electron). Snapshots an allowlist of state files; the app must be quit first.
public struct ClaudeDesktopAdapter: ToolAdapter {
    public let tool: Tool = .claudeDesktop
    public var processBundleID: String? { ClaudeDesktopConstants.bundleID }

    private let paths: Paths
    private let appPathsOverride: [String]?

    public init(paths: Paths, appPaths: [String]? = nil) {
        self.paths = paths
        self.appPathsOverride = appPaths
    }

    private var C: ClaudeDesktopConstants.Type { ClaudeDesktopConstants.self }
    private var dataDir: URL { paths.claudeDesktopDataDir }

    public func probe() async -> ToolProbe {
        let fm = FileManager.default
        let apps = appPathsOverride ?? C.appPaths
        guard let app = apps.first(where: { fm.fileExists(atPath: $0) }) else {
            return ToolProbe(status: .notInstalled)
        }
        let plist = URL(fileURLWithPath: app).appendingPathComponent("Contents/Info.plist")
        let info = (try? Data(contentsOf: plist)).flatMap {
            try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
        }
        guard let v = info?["CFBundleShortVersionString"] as? String else { return ToolProbe(status: .ok) }
        return ToolProbe(status: C.verifiedVersions.contains(v) ? .ok : .unverifiedVersion(v), version: v)
    }

    private func liveAccountUUID() throws -> String? {
        try JSONFile.readObject(dataDir.appendingPathComponent(C.configFile))?[C.accountKey] as? String
    }

    public func detectCurrentIdentity() async throws -> DetectedIdentity? {
        guard let uuid = try liveAccountUUID() else { return nil }
        // Enrich with the email when a Claude Code login for the same account exists.
        var hint: String?
        var org: String?
        if let oa = try JSONFile.readObject(paths.claudeJSON)?["oauthAccount"] as? [String: Any],
            oa["accountUuid"] as? String == uuid
        {
            hint = oa["emailAddress"] as? String
            org = oa["organizationName"] as? String
        }
        return DetectedIdentity(identityKey: uuid, displayHint: hint, organization: org)
    }

    public func capture() async throws -> StateBundle { try captureSync() }

    // Synchronous: DirectoryEnumerator can't be iterated from async contexts.
    private func captureSync() throws -> StateBundle {
        var b = StateBundle()
        let fm = FileManager.default
        for name in C.allowlist {
            let root = dataDir.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root.path, isDirectory: &isDir) else { continue }
            if !isDir.boolValue {
                try add(root, rel: name, to: &b)
                continue
            }
            guard let en = fm.enumerator(
                at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            else { continue }
            for case let url as URL in en {
                let vals = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard vals.isRegularFile == true, vals.isSymbolicLink != true else { continue }
                // Resolve symlinks on both sides (e.g. /var vs /private/var) before taking the suffix.
                let basePath = dataDir.resolvingSymlinksInPath().path
                let full = url.resolvingSymlinksInPath().path
                guard full.hasPrefix(basePath + "/") else { continue }
                try add(url, rel: String(full.dropFirst(basePath.count + 1)), to: &b)
            }
        }
        if let uuid = try liveAccountUUID() { b.meta["identityKey"] = uuid }
        return b
    }

    private func add(_ url: URL, rel: String, to b: inout StateBundle) throws {
        let data = try Data(contentsOf: url)
        b.entries.append(.init(path: rel, mode: FileUtil.posixMode(of: url) ?? 0o600, data: data))
    }

    private func isAllowed(_ rel: String) -> Bool {
        let comps = rel.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !rel.hasPrefix("/"), !comps.contains(".."), !comps.contains(""),
            let first = comps.first
        else { return false }
        return C.allowlist.contains(first)
    }

    private func clearManagedState() throws {
        let fm = FileManager.default
        for name in C.allowlist {
            let url = dataDir.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        }
    }

    public func apply(_ bundle: StateBundle) async throws {
        // Validate everything first so a bad bundle can't half-apply.
        for e in bundle.entries where !isAllowed(e.path) {
            throw SwaplaneError.invalidBundle("unexpected path in snapshot")
        }
        try clearManagedState()
        for e in bundle.entries {
            try FileUtil.atomicWrite(e.data, to: dataDir.appendingPathComponent(e.path), mode: e.mode)
        }
    }

    public func prepareEmpty() async throws { try clearManagedState() }

    public func verify(expectedIdentityKey: String?) async throws {
        let live = try liveAccountUUID()
        if let expected = expectedIdentityKey, live != expected {
            throw SwaplaneError.verifyFailed("restored account doesn't match the profile")
        }
        if expectedIdentityKey == nil, !FileManager.default.fileExists(
            atPath: dataDir.appendingPathComponent("Cookies").path)
        {
            throw SwaplaneError.verifyFailed("restored state is incomplete")
        }
    }
}
