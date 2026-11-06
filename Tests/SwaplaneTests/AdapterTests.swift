import XCTest
@testable import Adapters
@testable import SwaplaneCore

final class AdapterTests: XCTestCase {
    func testClaudeCodeCaptureApplyPreservesOtherKeys() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        try env.signInClaudeCode(uuid: "uuid-A", email: "alice@example.test", token: "FAKE-ACCESS-TOKEN-A")
        let a = env.codeAdapter()
        let id = try await a.detectCurrentIdentity()
        XCTAssertEqual(id?.identityKey, "uuid-A")
        let bundleA = try await a.capture()

        try env.signInClaudeCode(uuid: "uuid-B", email: "bob@example.test", token: "FAKE-ACCESS-TOKEN-B")
        try await a.apply(bundleA)
        XCTAssertEqual(try env.liveClaudeToken(), "FAKE-ACCESS-TOKEN-A")
        let cfg = try XCTUnwrap(JSONFile.readObject(env.paths.claudeJSON))
        XCTAssertEqual((cfg["oauthAccount"] as? [String: Any])?["accountUuid"] as? String, "uuid-A")
        XCTAssertEqual(cfg["userID"] as? String, "u-1")          // unrelated keys preserved
        XCTAssertNotNil(cfg["projects"])
    }

    func testClaudeCodeSignedOutDetectsNil() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let none = try await env.codeAdapter().detectCurrentIdentity()
        XCTAssertNil(none)
        do { _ = try await env.codeAdapter().capture(); XCTFail("expected throw") }
        catch { XCTAssertEqual(error as? SwaplaneError, .noCredentials(.claudeCode)) }
    }

    func testClaudeCodePrepareEmptySignsOut() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        try env.signInClaudeCode(uuid: "u", email: "a@example.test", token: "FAKE")
        try await env.codeAdapter().prepareEmpty()
        let id = try await env.codeAdapter().detectCurrentIdentity()
        XCTAssertNil(id)
        XCTAssertNil(try env.liveClaudeToken())
    }

    func testDesktopCaptureUsesAllowlistOnly() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        try env.signInDesktop(uuid: "uuid-A", cookies: "cookies-A")
        let b = try await env.desktopAdapter().capture()
        let paths = Set(b.entries.map(\.path))
        XCTAssertTrue(paths.contains("Cookies"))
        XCTAssertTrue(paths.contains("config.json"))
        XCTAssertTrue(paths.contains("Local Storage/leveldb/000003.log"))
        XCTAssertFalse(paths.contains { $0.hasPrefix("Cache") || $0.hasPrefix("vm_bundles") })
        XCTAssertEqual(b.meta["identityKey"], "uuid-A")
    }

    func testDesktopApplyRestoresAndLeavesCachesAlone() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let a = env.desktopAdapter()
        try env.signInDesktop(uuid: "uuid-A", cookies: "cookies-A")
        let bundleA = try await a.capture()
        try env.signInDesktop(uuid: "uuid-B", cookies: "cookies-B")
        try await a.apply(bundleA)
        XCTAssertEqual(env.liveCookies(), "cookies-A")
        try await a.verify(expectedIdentityKey: "uuid-A")
        let cache = try String(contentsOf: env.paths.claudeDesktopDataDir.appendingPathComponent("Cache/data_0"), encoding: .utf8)
        XCTAssertEqual(cache, "CACHE-JUNK")
        do { try await a.verify(expectedIdentityKey: "uuid-B"); XCTFail("expected throw") } catch {}
    }

    func testDesktopRejectsPathTraversalInBundle() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        for bad in ["../evil", "/etc/passwd", "Cache/x", "Cookies/../../x", ""] {
            let b = StateBundle(entries: [.init(path: bad, data: Data("x".utf8))])
            do { try await env.desktopAdapter().apply(b); XCTFail("accepted \(bad)") }
            catch { XCTAssertTrue(error is SwaplaneError) }
        }
    }

    func testDesktopIdentityEnrichedFromClaudeCode() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        try env.signInClaudeCode(uuid: "uuid-A", email: "alice@example.test", token: "FAKE")
        try env.signInDesktop(uuid: "uuid-A", cookies: "c")
        let id = try await env.desktopAdapter().detectCurrentIdentity()
        XCTAssertEqual(id?.displayHint, "alice@example.test")
    }

    func testDesktopProbe() async throws {
        let env = try TestEnv(); defer { env.cleanup() }
        let ok = await env.desktopAdapter().probe()
        XCTAssertEqual(ok.status, .ok)
        let missing = await ClaudeDesktopAdapter(paths: env.paths, appPaths: ["/nonexistent.app"]).probe()
        XCTAssertEqual(missing.status, .notInstalled)
    }
}
