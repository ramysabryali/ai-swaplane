import XCTest
@testable import SwaplaneCore
@testable import Usage

final class UsageTests: XCTestCase {
    private func credential(expiresInSeconds: Double, now: Date) -> Data {
        let ms = (now.timeIntervalSince1970 + expiresInSeconds) * 1000
        return Data("{\"claudeAiOauth\":{\"accessToken\":\"FAKE-ACCESS\",\"expiresAt\":\(ms)}}".utf8)
    }

    func testParseWindows() {
        let json = #"{"five_hour":{"utilization":62.5,"resets_at":"2026-11-06T18:00:00.123Z"},"seven_day":{"utilization":35,"resets_at":"2026-11-09T09:00:00Z"}}"#
        let w = UsageService.parse(Data(json.utf8))
        XCTAssertEqual(w?.map(\.name), ["Session", "Weekly"])
        XCTAssertEqual(w?.first?.percent, 62.5)
        XCTAssertNotNil(w?[1].resetsAt)
    }

    func testExpiredTokenMakesNoNetworkCall() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let now = Date()
        try env.keychain.write(service: "Claude Code-credentials", account: nil, data: credential(expiresInSeconds: -60, now: now))
        let called = CallBox()
        let svc = UsageService(paths: env.paths, keychain: env.keychain, fetch: { _ in called.hit(); return (Data(), 200) }, now: { now })
        let s = await svc.refreshLive(for: UUID())
        XCTAssertEqual(s.state, .expired)
        XCTAssertEqual(called.count, 0)
    }

    func testFreshThenStaleAndKeepsLastValuesWhenExpired() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let now = Date(); let gid = UUID()
        try env.keychain.write(service: "Claude Code-credentials", account: nil, data: credential(expiresInSeconds: 3600, now: now))
        let body = #"{"five_hour":{"utilization":40,"resets_at":"2026-11-06T18:00:00Z"},"seven_day":{"utilization":10}}"#
        let clock = ClockBox(now)
        let svc = UsageService(paths: env.paths, keychain: env.keychain, fetch: { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer FAKE-ACCESS")
            XCTAssertEqual(req.url?.host, "api.anthropic.com")
            return (Data(body.utf8), 200)
        }, now: { clock.value })
        let s = await svc.refreshLive(for: gid)
        XCTAssertEqual(s.state, .fresh)
        XCTAssertEqual(s.session?.percent, 40)
        clock.value = now.addingTimeInterval(600)
        let aged = await svc.snapshot(for: gid)
        XCTAssertEqual(aged?.state, .stale)
        // token now expired: previous numbers are kept, state reports why
        try env.keychain.write(service: "Claude Code-credentials", account: nil, data: credential(expiresInSeconds: -1, now: clock.value))
        let kept = await svc.refreshLive(for: gid)
        XCTAssertEqual(kept.state, .expired)
        XCTAssertEqual(kept.session?.percent, 40)
    }

    func test401AndFailuresNeverThrowAndNoSecretsOnDisk() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let now = Date()
        try env.keychain.write(service: "Claude Code-credentials", account: nil, data: credential(expiresInSeconds: 3600, now: now))
        let svc = UsageService(paths: env.paths, keychain: env.keychain, fetch: { _ in (Data(), 401) }, now: { now })
        let a = await svc.refreshLive(for: UUID()); XCTAssertEqual(a.state, .expired)
        let svc2 = UsageService(paths: env.paths, keychain: env.keychain, fetch: { _ in throw URLError(.notConnectedToInternet) }, now: { now })
        let b = await svc2.refreshLive(for: UUID()); XCTAssertEqual(b.state, .unavailable)
        let disk = (try? String(contentsOf: env.paths.usageFile, encoding: .utf8)) ?? ""
        XCTAssertFalse(disk.contains("FAKE-ACCESS"))
    }

    func testNoLimitPlan() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let svc = UsageService(paths: env.paths, keychain: env.keychain)
        let s = await svc.refreshLive(for: UUID(), planHasLimits: false)
        XCTAssertEqual(s.state, .none)
    }
}

final class CallBox: @unchecked Sendable {
    private let l = NSLock(); private var n = 0
    func hit() { l.withLock { n += 1 } }
    var count: Int { l.withLock { n } }
}
final class ClockBox: @unchecked Sendable {
    private let l = NSLock(); private var d: Date
    init(_ d: Date) { self.d = d }
    var value: Date { get { l.withLock { d } } set { l.withLock { d = newValue } } }
}
