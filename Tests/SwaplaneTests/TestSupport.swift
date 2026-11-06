import Foundation
import XCTest
@testable import Adapters
@testable import SwaplaneCore
@testable import SwitchEngine
@testable import Vault

final class InMemoryKeychain: KeychainClient, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    private func key(_ s: String, _ a: String?) -> String { "\(s)|\(a ?? "")" }

    private func resolve(_ s: String, _ a: String?) -> String? {
        if a != nil { return key(s, a) }
        return items.keys.first { $0.hasPrefix("\(s)|") }
    }
    func exists(service: String, account: String?) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        return resolve(service, account).map { items[$0] != nil } ?? false
    }
    func read(service: String, account: String?) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return resolve(service, account).flatMap { items[$0] }
    }
    func write(service: String, account: String?, data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        items[resolve(service, account) ?? key(service, account ?? "tester")] = data
    }
    func delete(service: String, account: String?) throws {
        lock.lock(); defer { lock.unlock() }
        if let k = resolve(service, account) { items[k] = nil }
    }
    var allValues: [Data] { lock.lock(); defer { lock.unlock() }; return Array(items.values) }
}

struct NoCommandRunner: CommandRunner {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async -> CommandResult? { nil }
}

final class FakeProcesses: ProcessController, @unchecked Sendable {
    private let lock = NSLock()
    private var _running = false
    private var _launches = 0
    private var _quits = 0
    var quitSucceeds = true
    var quitDelay: TimeInterval = 0
    var running: Bool {
        get { lock.withLock { _running } }
        set { lock.withLock { _running = newValue } }
    }
    var launches: Int { lock.withLock { _launches } }
    var quits: Int { lock.withLock { _quits } }
    func isRunning(bundleID: String) async -> Bool { running }
    func quit(bundleID: String, timeout: TimeInterval) async -> Bool {
        if quitDelay > 0 { try? await Task.sleep(nanoseconds: UInt64(quitDelay * 1e9)) }
        return lock.withLock {
            _quits += 1
            if quitSucceeds { _running = false }
            return quitSucceeds
        }
    }
    func launch(bundleID: String) async throws { lock.withLock { _launches += 1; _running = true } }
}

/// Wraps an adapter and injects faults after the real operation ran (to exercise rollback).
struct FaultyAdapter: ToolAdapter {
    let base: any ToolAdapter
    var failApplyForKey: String?
    var failVerifyForKey: String?
    var tool: Tool { base.tool }
    var processBundleID: String? { base.processBundleID }
    func probe() async -> ToolProbe { await base.probe() }
    func detectCurrentIdentity() async throws -> DetectedIdentity? { try await base.detectCurrentIdentity() }
    func capture() async throws -> StateBundle { try await base.capture() }
    func apply(_ bundle: StateBundle) async throws {
        try await base.apply(bundle)
        if let k = failApplyForKey, bundle.meta["identityKey"] == k { throw SwaplaneError.io("injected apply failure") }
    }
    func prepareEmpty() async throws { try await base.prepareEmpty() }
    func verify(expectedIdentityKey: String?) async throws {
        if let k = failVerifyForKey, expectedIdentityKey == k { throw SwaplaneError.verifyFailed("injected") }
        try await base.verify(expectedIdentityKey: expectedIdentityKey)
    }
}

struct TestEnv {
    let home: URL
    let paths: Paths
    let keychain = InMemoryKeychain()
    let vault: Vault
    let processes = FakeProcesses()
    let fakeApp: String

    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("swaplane-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        paths = Paths(home: home)
        vault = Vault(paths: paths, keychain: keychain)
        // Fake installed Claude.app so Desktop probe succeeds.
        let app = home.appendingPathComponent("Claude.app/Contents")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleShortVersionString": "4.16336.0"], format: .xml, options: 0)
        try plist.write(to: app.appendingPathComponent("Info.plist"))
        fakeApp = home.appendingPathComponent("Claude.app").path
    }

    func cleanup() { try? FileManager.default.removeItem(at: home) }

    func codeAdapter() -> ClaudeCodeAdapter {
        ClaudeCodeAdapter(paths: paths, keychain: keychain, runner: NoCommandRunner())
    }
    func desktopAdapter() -> ClaudeDesktopAdapter { ClaudeDesktopAdapter(paths: paths, appPaths: [fakeApp]) }

    func engine(_ adapters: [any ToolAdapter]? = nil, quitTimeout: TimeInterval = 1) -> SwitchEngine {
        SwitchEngine(paths: paths, vault: vault, adapters: adapters ?? [codeAdapter(), desktopAdapter()],
                     processes: processes, quitTimeout: quitTimeout)
    }

    // MARK: Fixtures (synthetic data only)

    func signInClaudeCode(uuid: String, email: String, token: String) throws {
        var cfg = (try? JSONFile.readObject(paths.claudeJSON)) ?? ["userID": "u-1", "projects": ["p": 1]]
        cfg["oauthAccount"] = ["accountUuid": uuid, "emailAddress": email, "organizationName": "Org"]
        try JSONFile.write(cfg, to: paths.claudeJSON)
        try keychain.write(service: "Claude Code-credentials", account: nil, data: Data(token.utf8))
    }
    func liveClaudeToken() throws -> String? {
        try keychain.read(service: "Claude Code-credentials", account: nil).map { String(decoding: $0, as: UTF8.self) }
    }

    func signInDesktop(uuid: String, cookies: String) throws {
        let d = paths.claudeDesktopDataDir
        func put(_ rel: String, _ s: String) throws {
            try FileUtil.atomicWrite(Data(s.utf8), to: d.appendingPathComponent(rel))
        }
        try put("Cookies", cookies)
        try put("config.json", "{\"lastKnownAccountUuid\":\"\(uuid)\",\"scale\":1}")
        try put("Local Storage/leveldb/000003.log", "ls-\(cookies)")
        try put("Cache/data_0", "CACHE-JUNK")            // must be excluded
        try put("vm_bundles/big.img", "VM-JUNK")         // must be excluded
    }
    func liveCookies() -> String? {
        (try? String(contentsOf: paths.claudeDesktopDataDir.appendingPathComponent("Cookies"), encoding: .utf8))
    }
}

extension JSONFile {
    static func readObjectPublic(_ url: URL) throws -> [String: Any]? { try readObject(url) }
}
