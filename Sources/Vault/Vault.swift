import CryptoKit
import Foundation
import SwaplaneCore

/// Owns profile metadata, per-profile sealed snapshots, the rollback store and app state.
/// Secrets only ever exist (a) in memory and (b) sealed on disk with a key held in the Keychain.
public actor Vault {
    public static let keychainService = "app.swaplane.vault"
    public static let rollbackRetention = 3

    private let paths: Paths
    private let keychain: KeychainClient

    public init(paths: Paths, keychain: KeychainClient) {
        self.paths = paths
        self.keychain = keychain
    }

    // MARK: Profiles

    public func profiles() throws -> [Profile] {
        guard let data = try? Data(contentsOf: paths.profilesFile) else { return [] }
        return try SwaplaneJSON.decoder.decode([Profile].self, from: data)
    }

    private func save(_ profiles: [Profile]) throws {
        try FileUtil.atomicWrite(try SwaplaneJSON.encoder.encode(profiles), to: paths.profilesFile)
    }

    public func profile(id: UUID) throws -> Profile? { try profiles().first { $0.id == id } }

    public func add(_ p: Profile) throws {
        var all = try profiles()
        all.append(p)
        try save(all)
    }

    public func update(_ p: Profile) throws {
        var all = try profiles()
        guard let i = all.firstIndex(where: { $0.id == p.id }) else { throw SwaplaneError.profileNotFound }
        all[i] = p
        try save(all)
    }

    /// Removes the profile and securely deletes its snapshot, key, and state references.
    public func remove(id: UUID) throws {
        var all = try profiles()
        guard all.contains(where: { $0.id == id }) else { throw SwaplaneError.profileNotFound }
        all.removeAll { $0.id == id }
        try save(all)
        let file = snapshotURL(id)
        if let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int), size > 0,
            let h = try? FileHandle(forWritingTo: file)
        {
            try? h.write(contentsOf: Data(count: size))   // best-effort overwrite (APFS limits apply)
            try? h.close()
        }
        try? FileManager.default.removeItem(at: file)
        try keychain.delete(service: Self.keychainService, account: snapshotKeyAccount(id))
        var st = try state()
        for (tool, active) in st.active where active == id { st.active[tool] = nil }
        for (tool, prev) in st.previous where prev == id { st.previous[tool] = nil }
        try saveState(st)
    }

    // MARK: State

    public func state() throws -> VaultState {
        guard let data = try? Data(contentsOf: paths.stateFile) else { return VaultState() }
        return try SwaplaneJSON.decoder.decode(VaultState.self, from: data)
    }

    private func saveState(_ s: VaultState) throws {
        try FileUtil.atomicWrite(try SwaplaneJSON.encoder.encode(s), to: paths.stateFile)
    }

    public func activeProfileID(for tool: Tool) throws -> UUID? { try state().active[tool.rawValue] }
    public func previousProfileID(for tool: Tool) throws -> UUID? { try state().previous[tool.rawValue] }

    public func setActive(_ id: UUID?, for tool: Tool) throws {
        var s = try state()
        if let old = s.active[tool.rawValue], old != id { s.previous[tool.rawValue] = old }
        s.active[tool.rawValue] = id
        try saveState(s)
    }

    // MARK: Snapshots

    private func snapshotURL(_ id: UUID) -> URL {
        paths.snapshotsDir.appendingPathComponent("\(id.uuidString).sealed")
    }
    private func snapshotKeyAccount(_ id: UUID) -> String { "\(id.uuidString):snapshotKey" }

    private func key(account: String, create: Bool) throws -> SymmetricKey? {
        if let raw = try keychain.read(service: Self.keychainService, account: account) {
            return SymmetricKey(data: raw)
        }
        guard create else { return nil }
        let k = SnapshotCrypto.newKey()
        try keychain.write(service: Self.keychainService, account: account, data: k.withUnsafeBytes { Data($0) })
        return k
    }

    public func saveSnapshot(_ bundle: StateBundle, for id: UUID) throws {
        let k = try key(account: snapshotKeyAccount(id), create: true)!
        let sealed = try SnapshotCrypto.seal(BundleCodec.encode(bundle), key: k)
        try FileUtil.atomicWrite(sealed, to: snapshotURL(id))
    }

    public func loadSnapshot(for id: UUID) throws -> StateBundle {
        guard let sealed = try? Data(contentsOf: snapshotURL(id)),
            let k = try key(account: snapshotKeyAccount(id), create: false)
        else { throw SwaplaneError.snapshotCorrupt }
        return try BundleCodec.decode(try SnapshotCrypto.open(sealed, key: k))
    }

    // MARK: Rollback store (pre-switch backups)

    private func rollbackDir(_ tool: Tool) -> URL {
        paths.rollbackDir.appendingPathComponent(tool.rawValue, isDirectory: true)
    }
    private func rollbackKeyAccount(_ tool: Tool) -> String { "rollback:\(tool.rawValue):key" }

    private func rollbackFiles(_ tool: Tool) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: rollbackDir(tool), includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "sealed" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public func saveRollback(_ bundle: StateBundle, tool: Tool, now: Date = Date()) throws {
        let k = try key(account: rollbackKeyAccount(tool), create: true)!
        let sealed = try SnapshotCrypto.seal(BundleCodec.encode(bundle), key: k)
        var stamp = Int(now.timeIntervalSince1970 * 1000)
        if let last = rollbackFiles(tool).last, let lastStamp = Int(last.deletingPathExtension().lastPathComponent),
            stamp <= lastStamp
        { stamp = lastStamp + 1 }
        let name = String(format: "%015d.sealed", stamp)
        try FileUtil.atomicWrite(sealed, to: rollbackDir(tool).appendingPathComponent(name))
        for old in rollbackFiles(tool).dropLast(Self.rollbackRetention) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    public func latestRollback(tool: Tool) throws -> StateBundle? {
        guard let f = rollbackFiles(tool).last else { return nil }
        guard let k = try key(account: rollbackKeyAccount(tool), create: false),
            let sealed = try? Data(contentsOf: f)
        else { throw SwaplaneError.snapshotCorrupt }
        return try BundleCodec.decode(try SnapshotCrypto.open(sealed, key: k))
    }

    public func rollbackCount(tool: Tool) -> Int { rollbackFiles(tool).count }
}
