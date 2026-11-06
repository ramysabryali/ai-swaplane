import XCTest
@testable import Adapters
@testable import SwaplaneCore
@testable import SwitchEngine
@testable import Vault

final class GroupTests: XCTestCase {
    /// Two accounts, each with a Code and a Desktop profile (synthetic data only).
    private func twoAccounts(_ env: TestEnv, _ engine: SwitchEngine) async throws -> (a: AccountGroup, b: AccountGroup) {
        try env.signInClaudeCode(uuid: "uuid-A", email: "alice@example.test", token: "TOKEN-A")
        try env.signInDesktop(uuid: "uuid-A", cookies: "COOKIES-A")
        let ac = try await engine.importCurrent(tool: .claudeCode, label: "A")
        _ = try await engine.importCurrent(tool: .claudeDesktop, label: "A", groupID: ac.groupID)
        try env.signInClaudeCode(uuid: "uuid-B", email: "bob@example.test", token: "TOKEN-B")
        try env.signInDesktop(uuid: "uuid-B", cookies: "COOKIES-B")
        let bc = try await engine.importCurrent(tool: .claudeCode, label: "B")
        _ = try await engine.importCurrent(tool: .claudeDesktop, label: "B", groupID: bc.groupID)
        let groups = try await env.vault.groups()
        return (groups.first { $0.id == ac.groupID }!, groups.first { $0.id == bc.groupID }!)
    }

    func testImportCreatesGroupAndLinksTools() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let engine = env.engine()
        let (a, _) = try await twoAccounts(env, engine)
        let members = try await env.vault.profiles().filter { $0.groupID == a.id }
        XCTAssertEqual(Set(members.map(\.tool)), [.claudeCode, .claudeDesktop])
        let all = try await env.vault.groups()
        XCTAssertEqual(all.count, 2)
    }

    func testSwitchGroupSwitchesBothAndCodeRunsFirst() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let engine = env.engine()
        let (a, _) = try await twoAccounts(env, engine)
        let order = OrderBox()
        let results = try await engine.switchGroup(a.id) { tool, phase in if phase == .preflight { order.add(tool) } }
        XCTAssertEqual(order.tools, [.claudeCode, .claudeDesktop])
        XCTAssertEqual(results.map(\.tool), [.claudeCode, .claudeDesktop])
        XCTAssertTrue(results.allSatisfy { if case .success = $0.result { true } else { false } })
        XCTAssertEqual(try env.liveClaudeToken(), "TOKEN-A")
        XCTAssertEqual(env.liveCookies(), "COOKIES-A")
    }

    func testSwitchGroupSingleTool() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let engine = env.engine()
        let (a, _) = try await twoAccounts(env, engine)
        let results = try await engine.switchGroup(a.id, tools: [.claudeCode])
        XCTAssertEqual(results.map(\.tool), [.claudeCode])
        XCTAssertEqual(try env.liveClaudeToken(), "TOKEN-A")
        XCTAssertEqual(env.liveCookies(), "COOKIES-B")      // Desktop untouched: mixed state
    }

    func testPartialFailureKeepsCodeSwitched() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let engine0 = env.engine()
        let (a, _) = try await twoAccounts(env, engine0)
        env.processes.running = true
        env.processes.quitSucceeds = false                     // Desktop won't quit
        let engine = env.engine(quitTimeout: 0.2)
        let results = try await engine.switchGroup(a.id)
        XCTAssertEqual(results.count, 2)
        if case .success = results[0].result {} else { XCTFail("Code should succeed") }
        if case .failure(let e) = results[1].result { XCTAssertEqual(e as? SwaplaneError, .appDidNotQuit("Claude Desktop")) } else { XCTFail("Desktop should fail") }
        XCTAssertEqual(try env.liveClaudeToken(), "TOKEN-A")
        XCTAssertEqual(env.liveCookies(), "COOKIES-B")
    }

    func testMigrationMergesAcrossToolsButKeepsSameToolDuplicatesApart() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let t0 = Date(timeIntervalSince1970: 1_000)
        let code1 = Profile(tool: .claudeCode, label: "Personal", identityKey: "k1", createdAt: t0)
        let desk1 = Profile(tool: .claudeDesktop, label: "Personal Desktop", identityKey: "k1", createdAt: t0 + 1)
        let code1b = Profile(tool: .claudeCode, label: "Personal copy", identityKey: "k1", createdAt: t0 + 2)
        let code2 = Profile(tool: .claudeCode, label: "Work", identityKey: "k2", createdAt: t0 + 3)
        for p in [code1, desk1, code1b, code2] { try await env.vault.add(p) }
        let changed = try await env.vault.migrateGroups()
        XCTAssertTrue(changed)
        let ps = try await env.vault.profiles()
        func gid(_ p: Profile) -> UUID? { ps.first { $0.id == p.id }?.groupID }
        XCTAssertNotNil(gid(code1))
        XCTAssertEqual(gid(code1), gid(desk1))           // merged across tools
        XCTAssertNotEqual(gid(code1), gid(code1b))       // same tool + same identity: separate
        XCTAssertNotEqual(gid(code1), gid(code2))
        let groups = try await env.vault.groups()
        XCTAssertEqual(groups.count, 3)
        let again = try await env.vault.migrateGroups()
        XCTAssertFalse(again)                             // idempotent
    }

    func testRemovingLastProfileRemovesGroup() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let engine = env.engine()
        let (a, _) = try await twoAccounts(env, engine)
        for p in try await env.vault.profiles().filter({ $0.groupID == a.id }) { try await env.vault.remove(id: p.id) }
        let groups = try await env.vault.groups()
        XCTAssertNil(groups.first { $0.id == a.id })
        XCTAssertEqual(groups.count, 1)
    }

    func testOneToolGroup() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let engine = env.engine()
        try env.signInClaudeCode(uuid: "uuid-A", email: "alice@example.test", token: "TOKEN-A")
        let p = try await engine.importCurrent(tool: .claudeCode, label: "Solo")
        let results = try await engine.switchGroup(p.groupID!)
        XCTAssertEqual(results.map(\.tool), [.claudeCode])     // Desktop skipped: no profile
    }
}

final class OrderBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _t: [Tool] = []
    func add(_ t: Tool) { lock.withLock { _t.append(t) } }
    var tools: [Tool] { lock.withLock { _t } }
}
