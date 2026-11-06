import XCTest
@testable import Adapters
@testable import SwaplaneCore
@testable import SwitchEngine
@testable import Vault

final class EngineTests: XCTestCase {
    // Synchronous: DirectoryEnumerator can't be iterated from async contexts.
    static func regularFiles(in dir: URL) -> [URL] {
        guard let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return en.compactMap { $0 as? URL }.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    // Helper: two Claude Code profiles A and B, B live/active at the end.
    private func twoCodeProfiles(_ env: TestEnv, _ engine: SwitchEngine) async throws -> (Profile, Profile) {
        try env.signInClaudeCode(uuid: "uuid-A", email: "alice@example.test", token: "FAKE-ACCESS-TOKEN-A")
        let a = try await engine.importCurrent(tool: .claudeCode, label: "A")
        try env.signInClaudeCode(uuid: "uuid-B", email: "bob@example.test", token: "FAKE-ACCESS-TOKEN-B")
        let b = try await engine.importCurrent(tool: .claudeCode, label: "B")
        return (a, b)
    }

    func testRoundTripSwitching() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let engine = env.engine()
        let (a, b) = try await twoCodeProfiles(env, engine)
        for _ in 0..<10 {
            try await engine.switchTo(a.id)
            XCTAssertEqual(try env.liveClaudeToken(), "FAKE-ACCESS-TOKEN-A")
            try await engine.switchTo(b.id)
            XCTAssertEqual(try env.liveClaudeToken(), "FAKE-ACCESS-TOKEN-B")
        }
        let active = try await env.vault.activeProfileID(for: .claudeCode)
        XCTAssertEqual(active, b.id)
        let prof = try await env.vault.profile(id: b.id)
        XCTAssertNotNil(prof?.lastUsedAt)
    }

    func testCaptureBackPreservesRefreshedToken() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let engine = env.engine()
        let (a, b) = try await twoCodeProfiles(env, engine)
        try await engine.switchTo(a.id)
        // The CLI refreshes the token while A is live:
        try env.keychain.write(service: "Claude Code-credentials", account: nil, data: Data("FAKE-REFRESHED-A".utf8))
        try await engine.switchTo(b.id)
        try await engine.switchTo(a.id)
        XCTAssertEqual(try env.liveClaudeToken(), "FAKE-REFRESHED-A")
    }

    func testSwitchToActiveIsNoOp() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let engine = env.engine()
        let (_, b) = try await twoCodeProfiles(env, engine)
        try await engine.switchTo(b.id)
        let n = await env.vault.rollbackCount(tool: .claudeCode)
        XCTAssertEqual(n, 0)
    }

    func testFailureAtApplyRollsBack() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let setup = env.engine()
        let (a, b) = try await twoCodeProfiles(env, setup)
        let faulty = FaultyAdapter(base: env.codeAdapter(), failApplyForKey: "uuid-A")
        let engine = env.engine([faulty])
        do { try await engine.switchTo(a.id); XCTFail("expected failure") } catch {}
        XCTAssertEqual(try env.liveClaudeToken(), "FAKE-ACCESS-TOKEN-B")     // restored
        let active = try await env.vault.activeProfileID(for: .claudeCode)
        XCTAssertEqual(active, b.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: env.paths.journalFile.path))
        let cfg = try XCTUnwrap(JSONFile.readObject(env.paths.claudeJSON))
        XCTAssertEqual((cfg["oauthAccount"] as? [String: Any])?["accountUuid"] as? String, "uuid-B")
    }

    func testFailureAtVerifyRollsBack() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let (a, _) = try await twoCodeProfiles(env, env.engine())
        let engine = env.engine([FaultyAdapter(base: env.codeAdapter(), failVerifyForKey: "uuid-A")])
        do { try await engine.switchTo(a.id); XCTFail("expected failure") } catch {}
        XCTAssertEqual(try env.liveClaudeToken(), "FAKE-ACCESS-TOKEN-B")
    }

    func testCrashRecoveryRestoresBackup() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let engine = env.engine()
        let (_, b) = try await twoCodeProfiles(env, engine)
        // Simulate: backup saved + journal written, then the process died after a partial apply.
        let backup = try await env.codeAdapter().capture()
        try await env.vault.saveRollback(backup, tool: .claudeCode)
        let json = "{\"tool\":\"claude-code\",\"targetID\":\"\(b.id.uuidString)\",\"startedAt\":\"2026-01-01T00:00:00Z\"}"
        try FileUtil.atomicWrite(Data(json.utf8), to: env.paths.journalFile)
        try env.keychain.write(service: "Claude Code-credentials", account: nil, data: Data("GARBAGE".utf8))
        let recovered = await env.engine().recoverIfNeeded()
        XCTAssertEqual(recovered, .claudeCode)
        XCTAssertEqual(try env.liveClaudeToken(), "FAKE-ACCESS-TOKEN-B")
        XCTAssertFalse(FileManager.default.fileExists(atPath: env.paths.journalFile.path))
        let again = await env.engine().recoverIfNeeded()
        XCTAssertNil(again)
    }

    func testTamperedSnapshotAbortsWithoutTouchingLiveState() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let engine = env.engine()
        let (a, _) = try await twoCodeProfiles(env, engine)
        let file = env.paths.snapshotsDir.appendingPathComponent("\(a.id.uuidString).sealed")
        var data = try Data(contentsOf: file); data[data.count - 2] ^= 0xFF
        try data.write(to: file)
        do { try await engine.switchTo(a.id); XCTFail("expected failure") }
        catch { XCTAssertEqual(error as? SwaplaneError, .snapshotCorrupt) }
        XCTAssertEqual(try env.liveClaudeToken(), "FAKE-ACCESS-TOKEN-B")
    }

    func testDriftAbortsThenDiscardProceeds() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let engine = env.engine()
        let (a, _) = try await twoCodeProfiles(env, engine)       // B active
        // User logs in as someone else outside Swaplane:
        try env.signInClaudeCode(uuid: "uuid-C", email: "carol@example.test", token: "FAKE-ACCESS-TOKEN-C")
        let drift = await engine.hasDrift(.claudeCode)
        XCTAssertTrue(drift)
        do { try await engine.switchTo(a.id); XCTFail("expected drift") }
        catch { XCTAssertEqual(error as? SwaplaneError, .drift(.claudeCode)) }
        XCTAssertEqual(try env.liveClaudeToken(), "FAKE-ACCESS-TOKEN-C")   // untouched
        try await engine.switchTo(a.id, onDrift: .discardLiveState)
        XCTAssertEqual(try env.liveClaudeToken(), "FAKE-ACCESS-TOKEN-A")
        // B's snapshot must NOT have been overwritten with C's state.
        let b = try await env.vault.profiles().first { $0.label == "B" }!
        try await engine.switchTo(b.id)
        XCTAssertEqual(try env.liveClaudeToken(), "FAKE-ACCESS-TOKEN-B")
    }

    func testSameEmailTwoDesktopProfilesStayIndependent() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let engine = env.engine()
        env.processes.running = true
        try env.signInDesktop(uuid: "uuid-SAME", cookies: "cookies-work")
        let work = try await engine.importCurrent(tool: .claudeDesktop, label: "Work")
        // Same account, separate state:
        try env.signInDesktop(uuid: "uuid-SAME", cookies: "cookies-experiments")
        let exp = try await engine.importCurrent(tool: .claudeDesktop, label: "Experiments")
        XCTAssertNotEqual(work.id, exp.id)
        XCTAssertEqual(work.identityKey, exp.identityKey)

        try await engine.switchTo(work.id)
        XCTAssertEqual(env.liveCookies(), "cookies-work")
        try env.signInDesktop(uuid: "uuid-SAME", cookies: "cookies-work-edited")   // change in Work
        try await engine.switchTo(exp.id)
        XCTAssertEqual(env.liveCookies(), "cookies-experiments")                    // unaffected
        try await engine.switchTo(work.id)
        XCTAssertEqual(env.liveCookies(), "cookies-work-edited")                    // edit preserved
        XCTAssertGreaterThan(env.processes.quits, 0)
        XCTAssertGreaterThan(env.processes.launches, 0)
    }

    func testAppThatWontQuitAbortsCleanly() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let engine = env.engine()
        try env.signInDesktop(uuid: "uuid-A", cookies: "cookies-A")
        let a = try await engine.importCurrent(tool: .claudeDesktop, label: "A")
        try env.signInDesktop(uuid: "uuid-B", cookies: "cookies-B")
        _ = try await engine.importCurrent(tool: .claudeDesktop, label: "B")
        env.processes.running = true
        env.processes.quitSucceeds = false
        do { try await engine.switchTo(a.id); XCTFail("expected failure") }
        catch { XCTAssertEqual(error as? SwaplaneError, .appDidNotQuit("Claude Desktop")) }
        XCTAssertEqual(env.liveCookies(), "cookies-B")
    }

    func testConcurrentSwitchOnSameToolIsRejected() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let engine = env.engine()
        try env.signInDesktop(uuid: "uuid-A", cookies: "cookies-A")
        let a = try await engine.importCurrent(tool: .claudeDesktop, label: "A")
        try env.signInDesktop(uuid: "uuid-B", cookies: "cookies-B")
        let b = try await engine.importCurrent(tool: .claudeDesktop, label: "B")
        env.processes.running = true
        env.processes.quitDelay = 0.4
        async let r1: Result<Void, Error> = Task { try await engine.switchTo(a.id) }.result
        try await Task.sleep(nanoseconds: 100_000_000)
        async let r2: Result<Void, Error> = Task { try await engine.switchTo(b.id) }.result
        let results = await [r1, r2]
        let failures = results.compactMap { r -> SwaplaneError? in
            if case .failure(let e) = r { return e as? SwaplaneError }; return nil
        }
        XCTAssertEqual(failures, [.switchInProgress(.claudeDesktop)])   // exactly one rejected
    }

    func testToolNotInstalledIsNonDestructive() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let missing = ClaudeDesktopAdapter(paths: env.paths, appPaths: ["/nonexistent.app"])
        let engine = env.engine([missing])
        do { _ = try await engine.importCurrent(tool: .claudeDesktop, label: "X"); XCTFail("expected failure") }
        catch { XCTAssertEqual(error as? SwaplaneError, .toolNotInstalled(.claudeDesktop)) }
    }

    func testBeginEmptySavesActiveAndSignsOut() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let engine = env.engine()
        let (_, b) = try await twoCodeProfiles(env, engine)
        try env.keychain.write(service: "Claude Code-credentials", account: nil, data: Data("FAKE-REFRESHED-B".utf8))
        try await engine.beginEmpty(tool: .claudeCode)
        XCTAssertNil(try env.liveClaudeToken())
        let active = try await env.vault.activeProfileID(for: .claudeCode)
        XCTAssertNil(active)
        try env.signInClaudeCode(uuid: "uuid-C", email: "carol@example.test", token: "FAKE-ACCESS-TOKEN-C")
        _ = try await engine.importCurrent(tool: .claudeCode, label: "C")
        try await engine.switchTo(b.id)
        XCTAssertEqual(try env.liveClaudeToken(), "FAKE-REFRESHED-B")     // refreshed token was saved back
    }

    func testReconcileActiveAfterRemovingActiveDuplicate() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let engine = env.engine()
        try env.signInClaudeCode(uuid: "uuid-A", email: "alice@example.test", token: "FAKE-ACCESS-TOKEN-A")
        let first = try await engine.importCurrent(tool: .claudeCode, label: "Personal")
        let dup = try await engine.importCurrent(tool: .claudeCode, label: "Personal")   // accidental duplicate, now active
        try await env.vault.remove(id: dup.id)
        let before = try await env.vault.activeProfileID(for: .claudeCode)
        XCTAssertNil(before)
        await engine.reconcileActive(.claudeCode)
        let after = try await env.vault.activeProfileID(for: .claudeCode)
        XCTAssertEqual(after, first.id)
        XCTAssertEqual(try env.liveClaudeToken(), "FAKE-ACCESS-TOKEN-A")                // live state untouched
    }

    // MARK: Security properties

    func testNoPlaintextSecretsOnDiskOrInLogs() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let engine = env.engine()
        let (a, b) = try await twoCodeProfiles(env, engine)
        try await engine.switchTo(a.id)
        try await engine.switchTo(b.id)
        let faulty = env.engine([FaultyAdapter(base: env.codeAdapter(), failApplyForKey: "uuid-A")])
        _ = try? await faulty.switchTo(a.id)

        var checked = 0
        for url in Self.regularFiles(in: env.paths.supportDir) {
            let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
            XCTAssertFalse(text.contains("FAKE-ACCESS-TOKEN"), "plaintext token in \(url.lastPathComponent)")
            XCTAssertFalse(text.contains("FAKE-REFRESHED"), "plaintext token in \(url.lastPathComponent)")
            XCTAssertEqual(FileUtil.posixMode(of: url), 0o600, "\(url.lastPathComponent) must be 0600")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 3)
        let dirs = [env.paths.supportDir, env.paths.snapshotsDir, env.paths.rollbackDir]
        for d in dirs { XCTAssertEqual(FileUtil.posixMode(of: d), 0o700, "\(d.lastPathComponent) must be 0700") }
        let log = try String(contentsOf: env.paths.activityLog, encoding: .utf8)
        XCTAssertFalse(log.contains("FAKE-"))
        XCTAssertTrue(log.contains("\"result\""))
    }

    func testRemoveProfileDeletesSnapshotAndKey() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let engine = env.engine()
        let (a, _) = try await twoCodeProfiles(env, engine)
        try await env.vault.remove(id: a.id)
        let file = env.paths.snapshotsDir.appendingPathComponent("\(a.id.uuidString).sealed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertNil(try env.keychain.read(service: Vault.keychainService, account: "\(a.id.uuidString):snapshotKey"))
        let profiles = try await env.vault.profiles()
        XCTAssertEqual(profiles.count, 1)
    }

    func testRollbackRetention() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let engine = env.engine()
        let (a, b) = try await twoCodeProfiles(env, engine)
        for _ in 0..<4 { try await engine.switchTo(a.id); try await engine.switchTo(b.id) }
        let n = await env.vault.rollbackCount(tool: .claudeCode)
        XCTAssertEqual(n, Vault.rollbackRetention)
    }
}
