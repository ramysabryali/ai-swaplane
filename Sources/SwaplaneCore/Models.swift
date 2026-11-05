import Foundation

/// A supported product surface.
public enum Tool: String, Codable, CaseIterable, Sendable, Hashable {
    case claudeCode = "claude-code"
    case claudeDesktop = "claude-desktop"

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .claudeDesktop: "Claude Desktop"
        }
    }

    public var symbolName: String {
        switch self {
        case .claudeCode: "terminal"
        case .claudeDesktop: "macwindow"
        }
    }
}

public enum IsolationMode: String, Codable, Sendable {
    /// Only credentials/identity are swapped; history and settings stay shared.
    case credentialsOnly
    /// Reserved: separate full config dir per profile (not implemented in v0.1).
    case fullIsolation
}

/// A profile = (tool, identity, isolated state bundle). Keyed by UUID, never by email.
public struct Profile: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var tool: Tool
    public var label: String
    /// Display only (e.g. masked email / org). Never used as a key.
    public var identityHint: String?
    /// Stable account identifier used for drift detection (e.g. accountUuid). Not secret.
    public var identityKey: String?
    public var colorName: String
    public var emoji: String?
    public var isolation: IsolationMode
    public var createdAt: Date
    public var lastUsedAt: Date?
    public var schemaVersion: Int

    public init(
        id: UUID = UUID(), tool: Tool, label: String, identityHint: String? = nil,
        identityKey: String? = nil, colorName: String = "blue", emoji: String? = nil,
        isolation: IsolationMode = .credentialsOnly, createdAt: Date = Date(),
        lastUsedAt: Date? = nil, schemaVersion: Int = 1
    ) {
        self.id = id
        self.tool = tool
        self.label = label
        self.identityHint = identityHint
        self.identityKey = identityKey
        self.colorName = colorName
        self.emoji = emoji
        self.isolation = isolation
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.schemaVersion = schemaVersion
    }
}

/// Non-secret app state persisted in `state.json`.
public struct VaultState: Codable, Sendable, Equatable {
    public var active: [String: UUID] = [:]
    public var previous: [String: UUID] = [:]
    public init() {}
}

/// Result of reading the live logged-in identity without side effects.
public struct DetectedIdentity: Sendable, Equatable {
    public var identityKey: String?
    public var displayHint: String?
    public var organization: String?
    public init(identityKey: String?, displayHint: String?, organization: String? = nil) {
        self.identityKey = identityKey
        self.displayHint = displayHint
        self.organization = organization
    }
}

public enum ProbeStatus: Sendable, Equatable {
    case ok
    /// Installed version has not been verified; switching allowed with a warning.
    case unverifiedVersion(String)
    case notInstalled
    case unsupported(String)

    public var allowsSwitching: Bool {
        switch self {
        case .ok, .unverifiedVersion: true
        case .notInstalled, .unsupported: false
        }
    }
}

public struct ToolProbe: Sendable, Equatable {
    public var status: ProbeStatus
    public var version: String?
    public init(status: ProbeStatus, version: String? = nil) {
        self.status = status
        self.version = version
    }
}

public enum SwitchPhase: String, Sendable {
    case preflight, stopping, backingUp, capturingBack, applying
    case relaunching, verifying, committing, rollingBack, done

    public var userText: String {
        switch self {
        case .preflight: "Checking…"
        case .stopping: "Quitting app…"
        case .backingUp: "Backing up current state…"
        case .capturingBack: "Saving current account…"
        case .applying: "Restoring account…"
        case .relaunching: "Relaunching…"
        case .verifying: "Verifying…"
        case .committing: "Finishing…"
        case .rollingBack: "Something went wrong — restoring previous account…"
        case .done: "Done"
        }
    }
}

public struct ActivityEntry: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID = UUID()
    public var date: Date
    public var tool: Tool
    public var fromLabel: String?
    public var toLabel: String?
    public var result: String
    public init(date: Date, tool: Tool, fromLabel: String?, toLabel: String?, result: String) {
        self.date = date
        self.tool = tool
        self.fromLabel = fromLabel
        self.toLabel = toLabel
        self.result = result
    }
}

/// Wraps a sensitive value so it never prints into logs or error descriptions.
public struct Redacted<Value: Sendable>: Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let value: Value
    public init(_ value: Value) { self.value = value }
    public var description: String { "‹redacted›" }
    public var debugDescription: String { "‹redacted›" }
    public var customMirror: Mirror { Mirror(self, children: []) }
}
