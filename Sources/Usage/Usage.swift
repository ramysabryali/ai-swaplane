import Foundation
import SwaplaneCore

/// One rate-limit window (e.g. the 5-hour session or the weekly cap).
public struct UsageWindow: Codable, Sendable, Equatable {
    public var name: String          // "Session" | "Weekly"
    public var percent: Double       // 0...100
    public var resetsAt: Date?
    public init(name: String, percent: Double, resetsAt: Date? = nil) {
        self.name = name
        self.percent = percent
        self.resetsAt = resetsAt
    }
}

public enum UsageState: String, Codable, Sendable {
    /// Fetched recently.
    case fresh
    /// Last known values; the live source can't be read right now.
    case stale
    /// The saved sign-in needs the CLI to refresh (or the user to sign in again).
    case expired
    /// The usage source failed or isn't available for this account.
    case unavailable
    /// The account has no usage limits (e.g. API key).
    case none
}

public struct UsageSnapshot: Codable, Sendable, Equatable {
    public var windows: [UsageWindow]
    public var fetchedAt: Date
    public var state: UsageState
    public init(windows: [UsageWindow], fetchedAt: Date, state: UsageState) {
        self.windows = windows
        self.fetchedAt = fetchedAt
        self.state = state
    }
    public var session: UsageWindow? { windows.first { $0.name == "Session" } }
    public var weekly: UsageWindow? { windows.first { $0.name == "Weekly" } }
}

public typealias UsageFetch = @Sendable (URLRequest) async throws -> (Data, Int)

/// Reads usage for the account that is live in Claude Code. Rules (docs/DESIGN.md §6):
/// - Uses only the token the CLI already holds; **never refreshes tokens** (rotation risk).
/// - Network goes to api.anthropic.com only, behind a feature flag. Failures never block switching.
/// - Percentages are cached (non-secret) per account so inactive accounts show "as of …" values.
/// The endpoint and its JSON shape are UNVERIFIED (SPIKE-0-FINDINGS.md, usage spike 2026-11-06).
public actor UsageService {
    enum Constants {
        // UNVERIFIED: endpoint is undocumented; the 2026-11-06 spike only confirmed it answers with an auth error for an expired token.
        static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        static let beta = "oauth-2025-04-20"
        static let keychainService = "Claude Code-credentials"
        static let staleAfter: TimeInterval = 300
    }

    private let paths: Paths
    private let keychain: KeychainClient
    private let fetch: UsageFetch
    private let now: @Sendable () -> Date
    private var cache: [String: UsageSnapshot]

    public init(
        paths: Paths, keychain: KeychainClient,
        fetch: @escaping UsageFetch = UsageService.urlSessionFetch, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.paths = paths
        self.keychain = keychain
        self.fetch = fetch
        self.now = now
        if let d = try? Data(contentsOf: paths.usageFile),
            let c = try? SwaplaneJSON.decoder.decode([String: UsageSnapshot].self, from: d)
        { cache = c } else { cache = [:] }
    }

    public static let urlSessionFetch: UsageFetch = { req in
        let (data, resp) = try await URLSession.shared.data(for: req)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Cached snapshot for an account, aged to `.stale` when old.
    public func snapshot(for group: UUID) -> UsageSnapshot? {
        guard var s = cache[group.uuidString] else { return nil }
        if s.state == .fresh, now().timeIntervalSince(s.fetchedAt) > Constants.staleAfter { s.state = .stale }
        return s
    }

    /// Fetches usage for the account currently live in Claude Code and stores it under `group`.
    @discardableResult
    public func refreshLive(for group: UUID, planHasLimits: Bool = true) async -> UsageSnapshot {
        let t = now()
        guard planHasLimits else { return store(UsageSnapshot(windows: [], fetchedAt: t, state: .none), group) }
        guard let token = liveToken() else { return keep(group, as: .unavailable) }
        if let exp = token.expiresAt, exp < t.addingTimeInterval(30) { return keep(group, as: .expired) }
        var req = URLRequest(url: Constants.endpoint, timeoutInterval: 15)
        req.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        req.setValue(Constants.beta, forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, status) = try await fetch(req)
            if status == 401 { return keep(group, as: .expired) }
            guard status == 200, let windows = Self.parse(data), !windows.isEmpty else { return keep(group, as: .unavailable) }
            return store(UsageSnapshot(windows: windows, fetchedAt: t, state: .fresh), group)
        } catch {
            return keep(group, as: .unavailable)
        }
    }

    // MARK: Internals

    private struct LiveToken { let value: String; let expiresAt: Date? }

    private func liveToken() -> LiveToken? {
        guard let raw = try? keychain.read(service: Constants.keychainService, account: nil),
            let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
            let oauth = obj["claudeAiOauth"] as? [String: Any],
            let access = oauth["accessToken"] as? String
        else { return nil }
        let exp = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return LiveToken(value: access, expiresAt: exp)
    }

    private func store(_ s: UsageSnapshot, _ g: UUID) -> UsageSnapshot {
        cache[g.uuidString] = s
        if let d = try? SwaplaneJSON.encoder.encode(cache) { try? FileUtil.atomicWrite(d, to: paths.usageFile) }
        return s
    }

    /// Keeps the last known percentages but reports why they aren't current.
    private func keep(_ g: UUID, as state: UsageState) -> UsageSnapshot {
        var s = cache[g.uuidString] ?? UsageSnapshot(windows: [], fetchedAt: now(), state: state)
        s.state = s.windows.isEmpty ? state : (state == .expired ? .expired : .stale)
        return store(s, g)
    }

    /// Tolerant parser for `{ "five_hour": {"utilization": 62.0, "resets_at": "…"}, "seven_day": {…} }`.
    static func parse(_ data: Data) -> [UsageWindow]? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        func window(_ key: String, _ name: String) -> UsageWindow? {
            guard let w = obj[key] as? [String: Any], let u = (w["utilization"] as? NSNumber)?.doubleValue else { return nil }
            let r = (w["resets_at"] as? String).flatMap { iso.date(from: $0) ?? plain.date(from: $0) }
            return UsageWindow(name: name, percent: min(100, max(0, u)), resetsAt: r)
        }
        return [window("five_hour", "Session"), window("seven_day", "Weekly")].compactMap { $0 }
    }
}
