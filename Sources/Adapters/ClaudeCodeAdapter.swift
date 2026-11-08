import Foundation
import SwaplaneCore

enum ClaudeCodeConstants {
    // VERIFIED: 2026-11-05 (CLI 1.0.83, macOS 27.2) — see docs/SPIKE-0-FINDINGS.md
    static let keychainService = "Claude Code-credentials"
    static let oauthKey = "oauthAccount"
    static let verifiedVersions: Set<String> = ["1.0.83"]
    static let secretName = "credential"
    static let oauthEntryPath = "oauthAccount.json"
    static let cliCandidates = [".claude/local/claude", ".local/bin/claude", ".npm-global/bin/claude"]
    static let absoluteCLICandidates = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
}

/// Claude Code (CLI), `credentialsOnly` mode: swaps the Keychain credential and the
/// `oauthAccount` block of `~/.claude.json`. Everything else in that file is preserved.
public struct ClaudeCodeAdapter: ToolAdapter {
    public let tool: Tool = .claudeCode
    public let processBundleID: String? = nil

    private let paths: Paths
    private let keychain: KeychainClient
    private let runner: CommandRunner

    public init(paths: Paths, keychain: KeychainClient, runner: CommandRunner = ProcessCommandRunner()) {
        self.paths = paths
        self.keychain = keychain
        self.runner = runner
    }

    private var C: ClaudeCodeConstants.Type { ClaudeCodeConstants.self }

    func cliPath() -> String? {
        let fm = FileManager.default
        let all = C.cliCandidates.map { paths.home.appendingPathComponent($0).path } + C.absoluteCLICandidates
        return all.first { fm.isExecutableFile(atPath: $0) }
    }

    public func probe() async -> ToolProbe {
        let hasConfig = FileManager.default.fileExists(atPath: paths.claudeJSON.path)
        guard let cli = cliPath() else {
            return ToolProbe(status: hasConfig ? .ok : .notInstalled)
        }
        var version: String?
        if let r = await runner.run(cli, ["--version"], timeout: 5), r.status == 0 {
            version = r.stdout.split(separator: " ").first.map(String.init)
        }
        guard let v = version else { return ToolProbe(status: .ok) }
        return ToolProbe(status: C.verifiedVersions.contains(v) ? .ok : .unverifiedVersion(v), version: v)
    }

    private func oauthAccount() throws -> [String: Any]? {
        try JSONFile.readObject(paths.claudeJSON)?[C.oauthKey] as? [String: Any]
    }

    public func detectCurrentIdentity() async throws -> DetectedIdentity? {
        guard let oa = try oauthAccount(),
            try keychain.exists(service: C.keychainService, account: nil)
        else { return nil }
        return DetectedIdentity(
            identityKey: oa["accountUuid"] as? String,
            displayHint: oa["emailAddress"] as? String,
            organization: oa["organizationName"] as? String)
    }

    public func capture() async throws -> StateBundle {
        guard let cred = try keychain.read(service: C.keychainService, account: nil) else {
            throw SwaplaneError.noCredentials(tool)
        }
        var b = StateBundle(secrets: [C.secretName: cred])
        if let oa = try oauthAccount() {
            b.entries.append(.init(
                path: C.oauthEntryPath,
                data: try JSONSerialization.data(withJSONObject: oa, options: [.sortedKeys])))
            if let key = oa["accountUuid"] as? String { b.meta["identityKey"] = key }
        }
        return b
    }

    public func apply(_ bundle: StateBundle) async throws {
        guard let cred = bundle.secrets[C.secretName] else { throw SwaplaneError.noCredentials(tool) }
        // Keychain first (update-in-place), then the identity block.
        try keychain.write(service: C.keychainService, account: nil, data: cred)
        var cfg = try JSONFile.readObject(paths.claudeJSON) ?? [:]
        if let entry = bundle.entries.first(where: { $0.path == C.oauthEntryPath }),
            let oa = try JSONSerialization.jsonObject(with: entry.data) as? [String: Any]
        {
            cfg[C.oauthKey] = oa
        } else {
            cfg[C.oauthKey] = nil
        }
        try JSONFile.write(cfg, to: paths.claudeJSON)
    }

    /// Reads the Claude Code credential once so macOS shows its access prompt now, with context.
    public func requestKeychainAccess() async -> KeychainAccess {
        do {
            guard try keychain.exists(service: C.keychainService, account: nil) else { return .notSignedIn }
            return try keychain.read(service: C.keychainService, account: nil) == nil ? .notSignedIn : .granted
        } catch { return .denied }
    }

    public func prepareEmpty() async throws {
        do {
            try keychain.delete(service: C.keychainService, account: nil)
        } catch SwaplaneError.keychain(let status) where status == -25244 || status == -25243 {
            // The item belongs to Claude Code, so macOS refuses to let another app delete it
            // (errSecInvalidOwnerEdit / errSecNoAccessForItem). Leave it: `/login` replaces it in place.
        }
        if var cfg = try JSONFile.readObject(paths.claudeJSON) {
            cfg[C.oauthKey] = nil
            try JSONFile.write(cfg, to: paths.claudeJSON)
        }
    }

    public func verify(expectedIdentityKey: String?) async throws {
        guard let id = try await detectCurrentIdentity() else {
            throw SwaplaneError.verifyFailed("not signed in after switching")
        }
        if let expected = expectedIdentityKey, id.identityKey != expected {
            throw SwaplaneError.verifyFailed("signed-in account doesn't match the profile")
        }
        // Best effort: `claude auth status` (JSON). Ignore tool errors; fail only on explicit loggedIn=false.
        if let cli = cliPath(),
            let r = await runner.run(cli, ["auth", "status"], timeout: 10), r.status == 0,
            let obj = try? JSONSerialization.jsonObject(with: Data(r.stdout.utf8)) as? [String: Any],
            obj["loggedIn"] as? Bool == false
        {
            throw SwaplaneError.verifyFailed("The CLI reports it is not logged in")
        }
    }
}

/// Result of asking macOS for access to the Claude Code Keychain item.
public enum KeychainAccess: Sendable, Equatable { case granted, notSignedIn, denied }
