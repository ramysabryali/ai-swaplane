import Foundation
import SwaplaneCore
import Vault
import Adapters

/// Transactional account switching. See docs/ARCHITECTURE.md "Switch transaction".
public actor SwitchEngine {
    public enum DriftResolution: Sendable { case abort, discardLiveState }

    private struct Journal: Codable {
        var tool: Tool
        var targetID: UUID
        var startedAt: Date
    }

    private let paths: Paths
    private let vault: Vault
    private let adapters: [Tool: any ToolAdapter]
    private let processes: ProcessController
    private let now: @Sendable () -> Date
    private let quitTimeout: TimeInterval
    private var inFlight: Set<Tool> = []

    public init(
        paths: Paths, vault: Vault, adapters: [any ToolAdapter], processes: ProcessController,
        quitTimeout: TimeInterval = 10, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.paths = paths
        self.vault = vault
        self.adapters = Dictionary(uniqueKeysWithValues: adapters.map { ($0.tool, $0) })
        self.processes = processes
        self.quitTimeout = quitTimeout
        self.now = now
    }

    private func adapter(_ tool: Tool) throws -> any ToolAdapter {
        guard let a = adapters[tool] else { throw SwaplaneError.unsupported(tool, "no adapter") }
        return a
    }

    // MARK: Queries

    public func probe(_ tool: Tool) async -> ToolProbe {
        guard let a = adapters[tool] else { return ToolProbe(status: .unsupported("no adapter")) }
        return await a.probe()
    }

    public func detectCurrent(_ tool: Tool) async throws -> DetectedIdentity? {
        try await adapter(tool).detectCurrentIdentity()
    }

    /// True when the live signed-in account differs from the active profile's account.
    public func hasDrift(_ tool: Tool) async -> Bool {
        guard let id = try? await vault.activeProfileID(for: tool),
            let p = try? await vault.profile(id: id), let expected = p.identityKey,
            let live = try? await adapters[tool]?.detectCurrentIdentity()
        else { return false }
        return live.identityKey != expected
    }

    /// When no profile is marked active but the live account matches a saved one (e.g. after removing
    /// the active profile), marks the most recently used matching profile active. Never changes live state.
    public func reconcileActive(_ tool: Tool) async {
        guard (try? await vault.activeProfileID(for: tool)) == nil,
            let live = try? await adapters[tool]?.detectCurrentIdentity(), let key = live.identityKey,
            let all = try? await vault.profiles(),
            let match = all.filter({ $0.tool == tool && $0.identityKey == key })
                .max(by: { ($0.lastUsedAt ?? $0.createdAt) < ($1.lastUsedAt ?? $1.createdAt) })
        else { return }
        try? await vault.setActive(match.id, for: tool)
    }

    // MARK: Import

    /// Saves the currently signed-in account as a new profile and marks it active.
    @discardableResult
    public func importCurrent(
        tool: Tool, label: String, colorName: String = "blue", emoji: String? = nil
    ) async throws -> Profile {
        let a = try adapter(tool)
        guard await a.probe().status.allowsSwitching else { throw SwaplaneError.toolNotInstalled(tool) }
        guard let identity = try await a.detectCurrentIdentity() else { throw SwaplaneError.noCredentials(tool) }
        let bundle = try await a.capture()
        let profile = Profile(
            tool: tool, label: label, identityHint: identity.displayHint,
            identityKey: identity.identityKey, colorName: colorName, emoji: emoji, createdAt: now())
        try await vault.saveSnapshot(bundle, for: profile.id)
        try await vault.add(profile)
        try await vault.setActive(profile.id, for: tool)
        return profile
    }

    /// Re-saves the live state into an existing profile ("re-import current state").
    public func recapture(profileID: UUID) async throws {
        guard let p = try await vault.profile(id: profileID) else { throw SwaplaneError.profileNotFound }
        let a = try adapter(p.tool)
        guard let identity = try await a.detectCurrentIdentity() else { throw SwaplaneError.noCredentials(p.tool) }
        try await vault.saveSnapshot(try await a.capture(), for: p.id)
        var updated = p
        updated.identityKey = identity.identityKey
        updated.identityHint = identity.displayHint ?? p.identityHint
        try await vault.update(updated)
    }

    /// First half of "create empty profile": saves the active account back, quits the app,
    /// backs up and signs the tool out so the user can sign in with another account.
    /// Finish with `importCurrent`.
    public func beginEmpty(tool: Tool, progress: @escaping @Sendable (SwitchPhase) -> Void = { _ in }) async throws {
        try lock(tool)
        defer { inFlight.remove(tool) }
        let a = try adapter(tool)
        guard await a.probe().status.allowsSwitching else { throw SwaplaneError.toolNotInstalled(tool) }
        if let bid = a.processBundleID, await processes.isRunning(bundleID: bid) {
            progress(.stopping)
            guard await processes.quit(bundleID: bid, timeout: quitTimeout) else {
                throw SwaplaneError.appDidNotQuit(tool.displayName)
            }
        }
        progress(.backingUp)
        let live = try await a.capture()
        try await vault.saveRollback(live, tool: tool, now: now())
        if let activeID = try await vault.activeProfileID(for: tool) { try await vault.saveSnapshot(live, for: activeID) }
        try await a.prepareEmpty()
        try await vault.setActive(nil, for: tool)
        progress(.done)
    }

    // MARK: Switch

    private func lock(_ tool: Tool) throws {
        guard inFlight.insert(tool).inserted else { throw SwaplaneError.switchInProgress(tool) }
    }

    public func switchTo(
        _ profileID: UUID, onDrift: DriftResolution = .abort,
        progress: @escaping @Sendable (SwitchPhase) -> Void = { _ in }
    ) async throws {
        guard let target = try await vault.profile(id: profileID) else { throw SwaplaneError.profileNotFound }
        let tool = target.tool
        try lock(tool)
        defer { inFlight.remove(tool) }

        let a = try adapter(tool)
        let activeID = try await vault.activeProfileID(for: tool)
        if activeID == profileID { progress(.done); return }
        var active: Profile?
        if let activeID { active = try await vault.profile(id: activeID) }

        // 1. Preflight
        progress(.preflight)
        let status = await a.probe().status
        guard status.allowsSwitching else {
            throw status == .notInstalled
                ? SwaplaneError.toolNotInstalled(tool)
                : SwaplaneError.unsupported(tool, "this version isn't supported")
        }
        let targetBundle = try await vault.loadSnapshot(for: profileID)   // fails early if corrupt

        // 2. Stop the app (desktop only)
        var wasRunning = false
        if let bid = a.processBundleID, await processes.isRunning(bundleID: bid) {
            wasRunning = true
            progress(.stopping)
            guard await processes.quit(bundleID: bid, timeout: quitTimeout) else {
                throw SwaplaneError.appDidNotQuit(tool.displayName)
            }
        }

        // 3. Backup live state
        progress(.backingUp)
        let live = try await a.capture()
        try await vault.saveRollback(live, tool: tool, now: now())
        try writeJournal(Journal(tool: tool, targetID: profileID, startedAt: now()))

        do {
            // 4. Capture-back (preserves refreshed tokens / in-app changes), unless live state
            //    belongs to a different account than the active profile.
            progress(.capturingBack)
            if let active {
                let liveKey = live.meta["identityKey"]
                if let expected = active.identityKey, let liveKey, liveKey != expected {
                    if onDrift == .abort { throw SwaplaneError.drift(tool) }
                } else {
                    try await vault.saveSnapshot(live, for: active.id)
                }
            }

            // 5. Apply target
            progress(.applying)
            try await a.apply(targetBundle)

            // 6. Relaunch
            if wasRunning, let bid = a.processBundleID {
                progress(.relaunching)
                try? await processes.launch(bundleID: bid)
            }

            // 7. Verify
            progress(.verifying)
            try await a.verify(expectedIdentityKey: target.identityKey)
        } catch {
            progress(.rollingBack)
            try? await a.apply(live)
            if wasRunning, let bid = a.processBundleID { try? await processes.launch(bundleID: bid) }
            clearJournal()
            logActivity(tool: tool, from: active?.label, to: target.label, result: "failed: \(Self.safe(error))")
            throw error
        }

        // 8. Commit
        progress(.committing)
        try await vault.setActive(profileID, for: tool)
        var updated = target
        updated.lastUsedAt = now()
        try await vault.update(updated)
        clearJournal()
        logActivity(tool: tool, from: active?.label, to: target.label, result: "ok")
        progress(.done)
    }

    // MARK: Crash recovery

    /// Call at launch. If a switch was interrupted after the backup, restore the backup.
    @discardableResult
    public func recoverIfNeeded() async -> Tool? {
        guard let j = readJournal() else { return nil }
        defer { clearJournal() }
        guard let a = adapters[j.tool], let backup = try? await vault.latestRollback(tool: j.tool) else { return nil }
        try? await a.apply(backup)
        logActivity(tool: j.tool, from: nil, to: nil, result: "recovered interrupted switch")
        return j.tool
    }

    // MARK: Journal & activity

    private func writeJournal(_ j: Journal) throws {
        try FileUtil.atomicWrite(try SwaplaneJSON.encoder.encode(j), to: paths.journalFile)
    }
    private func readJournal() -> Journal? {
        (try? Data(contentsOf: paths.journalFile)).flatMap { try? SwaplaneJSON.decoder.decode(Journal.self, from: $0) }
    }
    private func clearJournal() { try? FileManager.default.removeItem(at: paths.journalFile) }

    /// Error text safe for logs: only our own secret-free messages.
    private static func safe(_ error: Error) -> String {
        (error as? SwaplaneError)?.errorDescription ?? "unexpected error"
    }

    private func logActivity(tool: Tool, from: String?, to: String?, result: String) {
        let entry = ActivityEntry(date: now(), tool: tool, fromLabel: from, toLabel: to, result: result)
        guard var line = try? JSONEncoder.iso.encode(entry) else { return }
        line.append(0x0A)
        try? FileUtil.ensureDir(paths.activityLog.deletingLastPathComponent())
        if let h = try? FileHandle(forWritingTo: paths.activityLog) {
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: line)
            try? h.close()
        } else {
            try? FileUtil.atomicWrite(line, to: paths.activityLog)
        }
    }

    public func activity(limit: Int = 200) -> [ActivityEntry] {
        guard let text = try? String(contentsOf: paths.activityLog, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").suffix(limit).compactMap {
            try? SwaplaneJSON.decoder.decode(ActivityEntry.self, from: Data($0.utf8))
        }.reversed()
    }
}

extension JSONEncoder {
    fileprivate static var iso: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
