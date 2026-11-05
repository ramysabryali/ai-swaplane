import Adapters
import Foundation
import Observation
import SwaplaneCore
import SwitchEngine
import Vault

public struct Toast: Identifiable, Equatable {
    public let id = UUID()
    public var message: String
    /// Profile to switch back to if the user taps Undo.
    public var undoProfileID: UUID?
}

public enum Mask {
    /// "alice@example.com" -> "a***@example.com"
    public static func email(_ s: String) -> String {
        guard let at = s.firstIndex(of: "@"), at != s.startIndex else { return s }
        return "\(s[s.startIndex])***\(s[at...])"
    }
}

@MainActor @Observable
public final class AppModel {
    public private(set) var profiles: [Profile] = []
    public private(set) var activeByTool: [Tool: UUID] = [:]
    public private(set) var probes: [Tool: ToolProbe] = [:]
    public private(set) var detected: [Tool: DetectedIdentity] = [:]
    public private(set) var drift: Set<Tool> = []
    public private(set) var activity: [ActivityEntry] = []
    public var phase: SwitchPhase?
    public var switchingTool: Tool?
    public var toast: Toast?
    public var errorMessage: String?
    public var showWizard = false
    /// Tool pre-selected when the import wizard opens.
    public var wizardTool: Tool = .claudeCode
    /// Set while the user is signing in to a fresh account ("create empty profile" flow).
    public var pendingEmptyTool: Tool?

    public var maskEmails: Bool {
        didSet { UserDefaults.standard.set(maskEmails, forKey: "maskEmails") }
    }

    @ObservationIgnored public var onChange: (() -> Void)?
    @ObservationIgnored public var onOpenMainWindow: (() -> Void)?
    @ObservationIgnored public var onQuit: (() -> Void)?

    let engine: SwitchEngine
    let vault: Vault

    public init(engine: SwitchEngine, vault: Vault) {
        self.engine = engine
        self.vault = vault
        self.maskEmails = UserDefaults.standard.object(forKey: "maskEmails") as? Bool ?? true
    }

    public func display(_ hint: String?) -> String? {
        guard let hint else { return nil }
        return maskEmails ? Mask.email(hint) : hint
    }

    public func openWizard(_ tool: Tool? = nil) {
        if let tool { wizardTool = tool }
        showWizard = true
        onOpenMainWindow?()
    }

    public func profiles(for tool: Tool) -> [Profile] { profiles.filter { $0.tool == tool } }
    public func isActive(_ p: Profile) -> Bool { activeByTool[p.tool] == p.id }
    public func activeProfile(for tool: Tool) -> Profile? {
        activeByTool[tool].flatMap { id in profiles.first { $0.id == id } }
    }

    public func reload() async {
        profiles = (try? await vault.profiles()) ?? []
        var active: [Tool: UUID] = [:]
        var newDrift: Set<Tool> = []
        for tool in Tool.allCases {
            active[tool] = try? await vault.activeProfileID(for: tool)
            probes[tool] = await engine.probe(tool)
            if probes[tool]?.status != .notInstalled {
                detected[tool] = try? await engine.detectCurrent(tool)
            } else { detected[tool] = nil }
            if await engine.hasDrift(tool) { newDrift.insert(tool) }
        }
        activeByTool = active
        drift = newDrift
        activity = await engine.activity()
        onChange?()
    }

    private func run(_ tool: Tool?, _ work: () async throws -> Void) async {
        errorMessage = nil
        switchingTool = tool
        do { try await work() }
        catch { errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong." }
        phase = nil
        switchingTool = nil
        await reload()
    }

    public func switchTo(_ p: Profile, discardDrift: Bool = false) async {
        let previous = activeByTool[p.tool]
        await run(p.tool) {
            try await engine.switchTo(p.id, onDrift: discardDrift ? .discardLiveState : .abort) { [weak self] ph in
                Task { @MainActor in self?.phase = ph }
            }
            toast = Toast(message: "Switched \(p.tool.displayName) to \(p.label)", undoProfileID: previous)
        }
    }

    public func undo(_ t: Toast) async {
        toast = nil
        guard let id = t.undoProfileID, let p = profiles.first(where: { $0.id == id }) else { return }
        await switchTo(p)
        toast = nil
    }

    public func importCurrent(tool: Tool, label: String, colorName: String, emoji: String?) async -> Bool {
        var ok = false
        await run(tool) {
            _ = try await engine.importCurrent(tool: tool, label: label, colorName: colorName, emoji: emoji)
            ok = true
        }
        if ok { pendingEmptyTool = nil }
        return ok
    }

    public func beginEmpty(tool: Tool) async -> Bool {
        var ok = false
        await run(tool) {
            try await engine.beginEmpty(tool: tool) { [weak self] ph in Task { @MainActor in self?.phase = ph } }
            pendingEmptyTool = tool
            ok = true
        }
        return ok
    }

    public func rename(_ p: Profile, to label: String, colorName: String, emoji: String?) async {
        var u = p
        u.label = label; u.colorName = colorName; u.emoji = emoji
        await run(nil) { try await vault.update(u) }
    }

    public func recapture(_ p: Profile) async { await run(p.tool) { try await engine.recapture(profileID: p.id) } }
    public func remove(_ p: Profile) async {
        await run(nil) {
            try await vault.remove(id: p.id)
            await engine.reconcileActive(p.tool)
        }
    }
}
