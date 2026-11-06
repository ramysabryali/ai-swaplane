import Adapters
import AppKit
import Foundation
import Observation
import SwaplaneCore
import SwitchEngine
import Usage
import Vault

public enum ToastAction: Equatable {
    case undo([Tool: UUID])
    case retry(Tool, UUID)
}

public struct Toast: Identifiable, Equatable {
    public let id = UUID()
    public var message: String
    public var actions: [ToastAction] = []
    public var isError = false
}

public enum Mask {
    /// "alice@example.com" -> "a***@example.com"
    public static func email(_ s: String) -> String {
        guard let at = s.firstIndex(of: "@"), at != s.startIndex else { return s }
        return "\(s[s.startIndex])***\(s[at...])"
    }
}

/// One lane: an account with its per-tool profiles.
public struct Account: Identifiable, Equatable {
    public let group: AccountGroup
    public let profiles: [Tool: Profile]
    public var id: UUID { group.id }
    public var tools: [Tool] { Tool.allCases.filter { profiles[$0] != nil } }
    var identityHint: String? { tools.compactMap { profiles[$0]?.identityHint }.first }
}

public enum TargetChoice: Equatable { case all, only(Tool) }

@MainActor @Observable
public final class AppModel {
    // Data
    public private(set) var groups: [AccountGroup] = []
    public private(set) var profiles: [Profile] = []
    public private(set) var activeByTool: [Tool: UUID] = [:]
    public private(set) var probes: [Tool: ToolProbe] = [:]
    public private(set) var detected: [Tool: DetectedIdentity] = [:]
    public private(set) var drift: Set<Tool> = []
    public private(set) var activity: [ActivityEntry] = []
    public private(set) var usage: [UUID: UsageSnapshot] = [:]
    public private(set) var loaded = false

    // Panel state
    public var selectedID: UUID?
    public var target: TargetChoice = .all
    public var busy = false
    public var phaseText: String?
    public var toast: Toast?
    public var errorMessage: String?
    public var renamingID: UUID?
    public var removingID: UUID?
    /// Bumped after a successful switch; drives the connector draw / node pulse.
    public private(set) var flashID: UUID?
    public private(set) var flashTick = 0
    public private(set) var reminders: [UUID: ReminderPrefs] = [:]

    // Wizard
    public var showWizard = false
    public var wizardTool: Tool = .claudeCode
    public var wizardGroupID: UUID?
    public var pendingEmptyTool: Tool?
    /// Set when the wizard is re-authenticating an existing profile.
    public var reauthProfile: Profile?

    // Settings
    public var appearance: AppearanceMode {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance"); NSApp?.appearance = appearance.nsAppearance }
    }
    public var soundEnabled: Bool { didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") } }
    public var reduceMotionSetting: Bool { didSet { UserDefaults.standard.set(reduceMotionSetting, forKey: "reduceMotion") } }
    public var maskEmails: Bool { didSet { UserDefaults.standard.set(maskEmails, forKey: "maskEmails") } }
    public var usageEnabled: Bool {
        didSet { UserDefaults.standard.set(usageEnabled, forKey: "usageEnabled"); if usageEnabled { Task { await refreshUsage() } } }
    }

    @ObservationIgnored public var onChange: (() -> Void)?
    @ObservationIgnored public var onOpenSettings: (() -> Void)?
    @ObservationIgnored public var onOpenWizard: (() -> Void)?
    @ObservationIgnored public var onClosePanel: (() -> Void)?
    @ObservationIgnored public var onQuit: (() -> Void)?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    let engine: SwitchEngine
    let vault: Vault
    let usageService: UsageService

    public init(engine: SwitchEngine, vault: Vault, usage: UsageService) {
        self.engine = engine
        self.vault = vault
        self.usageService = usage
        let d = UserDefaults.standard
        appearance = AppearanceMode(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        soundEnabled = d.object(forKey: "soundEnabled") as? Bool ?? true
        reduceMotionSetting = d.bool(forKey: "reduceMotion")
        maskEmails = d.object(forKey: "maskEmails") as? Bool ?? true
        usageEnabled = d.object(forKey: "usageEnabled") as? Bool ?? true
        if let data = d.data(forKey: "reminders"),
            let r = try? JSONDecoder().decode([String: ReminderPrefs].self, from: data)
        { reminders = Dictionary(uniqueKeysWithValues: r.compactMap { k, v in UUID(uuidString: k).map { ($0, v) } }) }
    }

    // MARK: Derived

    public var motion: Bool { !(reduceMotionSetting || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) }

    public var accounts: [Account] {
        groups.sorted { $0.createdAt < $1.createdAt }.map { g in
            var per: [Tool: Profile] = [:]
            for p in profiles where p.groupID == g.id { per[p.tool] = p }
            return Account(group: g, profiles: per)
        }
    }
    public var selected: Account? {
        let all = accounts
        return all.first { $0.id == selectedID } ?? activeAccount(for: .claudeCode) ?? all.first
    }
    public func activeAccount(for tool: Tool) -> Account? {
        guard let pid = activeByTool[tool], let gid = profiles.first(where: { $0.id == pid })?.groupID else { return nil }
        return accounts.first { $0.id == gid }
    }
    public func isActive(_ a: Account, on tool: Tool) -> Bool { a.profiles[tool].map { activeByTool[tool] == $0.id } ?? false }
    public func activeTools(_ a: Account) -> [Tool] { Tool.allCases.filter { isActive(a, on: $0) } }
    public func display(_ hint: String?) -> String? {
        guard let hint else { return nil }
        return maskEmails ? Mask.email(hint) : hint
    }
    public func reminder(for id: UUID) -> ReminderPrefs { reminders[id] ?? ReminderPrefs() }

    /// Tools that "Switch" would act on for the selected account, given the Both / only choice.
    public func candidateTools(for a: Account) -> [Tool] { a.tools.filter { !isActive(a, on: $0) } }
    public func switchTools(for a: Account) -> [Tool] {
        let c = candidateTools(for: a)
        if case .only(let t) = target, c.contains(t) { return [t] }
        return c
    }

    /// Whether a tool needs a profile for this account (offer "add Desktop to this account").
    public func missingTools(_ a: Account) -> [Tool] {
        Tool.allCases.filter { a.profiles[$0] == nil && (probes[$0]?.status.allowsSwitching ?? false) }
    }

    /// Detected live account that isn't saved yet, per tool.
    public func unsaved(_ tool: Tool) -> DetectedIdentity? {
        guard let d = detected[tool] else { return nil }
        if let key = d.identityKey, profiles.contains(where: { $0.tool == tool && $0.identityKey == key }) { return nil }
        return d
    }

    // MARK: Snapshot seeding (developer aid, synthetic data only)

    func seedForSnapshot(_ scenario: String) {
        let t0 = Date(timeIntervalSince1970: 1_000)
        func g(_ n: String, _ c: String, _ i: Double) -> AccountGroup { AccountGroup(label: n, colorName: c, createdAt: t0 + i) }
        var gs: [AccountGroup] = []
        var ps: [Profile] = []
        var snaps: [UUID: UsageSnapshot] = [:]
        let now = Date()
        func win(_ s: Double, _ w: Double?) -> [UsageWindow] {
            [UsageWindow(name: "Session", percent: s, resetsAt: now.addingTimeInterval(4300))]
                + (w.map { [UsageWindow(name: "Weekly", percent: $0, resetsAt: now.addingTimeInterval(200_000))] } ?? [])
        }
        func add(_ grp: AccountGroup, _ email: String, tools: [Tool] = Tool.allCases) {
            gs.append(grp)
            for t in tools { ps.append(Profile(tool: t, label: grp.label, identityHint: email, identityKey: grp.id.uuidString, colorName: grp.colorName, groupID: grp.id)) }
        }
        var act: [Tool: UUID] = [:]
        switch scenario {
        case "empty", "welcome":
            break
        case "one":
            let p = g("Personal", "blue", 0); add(p, "alice@example.com")
            snaps[p.id] = UsageSnapshot(windows: win(62, 35), fetchedAt: now, state: .fresh)
            for t in Tool.allCases { act[t] = ps.first { $0.tool == t }?.id }
        default:
            let a = g("Personal", "blue", 0), b = g("Work", "green", 1), c = g("Client A", "purple", 2), d = g("Old team", "yellow", 3)
            add(a, "alice@example.com"); add(b, "alice@work.example"); add(c, "client@example.com", tools: [.claudeCode]); add(d, "old@example.com")
            snaps[a.id] = UsageSnapshot(windows: win(62, 35), fetchedAt: now, state: .fresh)
            snaps[b.id] = UsageSnapshot(windows: win(18, 81), fetchedAt: now.addingTimeInterval(-900), state: .stale)
            snaps[c.id] = UsageSnapshot(windows: [], fetchedAt: now, state: .none)
            snaps[d.id] = UsageSnapshot(windows: [], fetchedAt: now, state: .unavailable)
            if scenario == "many" {
                for i in 0..<4 { let x = g("Account \(i + 5)", Palette.names[i], Double(4 + i)); add(x, "x\(i)@example.com"); snaps[x.id] = UsageSnapshot(windows: win(Double(10 + i * 25), Double(20 + i * 20)), fetchedAt: now, state: .fresh) }
            }
            act[.claudeCode] = ps.first { $0.groupID == a.id && $0.tool == .claudeCode }?.id
            act[.claudeDesktop] = ps.first { $0.groupID == b.id && $0.tool == .claudeDesktop }?.id
        }
        groups = gs; profiles = ps; activeByTool = act; usage = snaps
        probes = [.claudeCode: ToolProbe(status: .ok), .claudeDesktop: ToolProbe(status: .ok)]
        detected = scenario == "welcome" ? [.claudeCode: DetectedIdentity(identityKey: "k", displayHint: "alice@example.com"), .claudeDesktop: DetectedIdentity(identityKey: "k", displayHint: "alice@example.com")] : [:]
        selectedID = gs.count > 1 ? gs[1].id : gs.first?.id
        toast = scenario == "multi" ? Toast(message: "Switched Code to Personal", actions: [.undo([:])]) : nil
        loaded = true
    }

    // MARK: Load

    public func reload() async {
        _ = try? await vault.migrateGroups()
        profiles = (try? await vault.profiles()) ?? []
        groups = (try? await vault.groups()) ?? []
        var active: [Tool: UUID] = [:]
        var newDrift: Set<Tool> = []
        for tool in Tool.allCases {
            active[tool] = try? await vault.activeProfileID(for: tool)
            probes[tool] = await engine.probe(tool)
            if probes[tool]?.status != .notInstalled { detected[tool] = try? await engine.detectCurrent(tool) } else { detected[tool] = nil }
            if await engine.hasDrift(tool) { newDrift.insert(tool) }
        }
        activeByTool = active
        drift = newDrift
        activity = await engine.activity()
        for g in groups { if let s = await usageService.snapshot(for: g.id) { usage[g.id] = s } }
        if selectedID == nil || !groups.contains(where: { $0.id == selectedID }) { selectedID = selected?.id }
        loaded = true
        onChange?()
    }

    public func refreshUsage() async {
        guard usageEnabled, let a = activeAccount(for: .claudeCode) else { return }
        let snap = await usageService.refreshLive(for: a.id)
        usage[a.id] = snap
        Reminders.sync(group: a.id, label: a.group.label, prefs: reminder(for: a.id), snapshot: snap)
        onChange?()
    }

    // MARK: Selection and presentation

    public func select(_ id: UUID) {
        guard !busy, selectedID != id else { return }
        selectedID = id
        target = .all
        removingID = nil
        SoundPlayer.shared.play(.select)
    }

    public func showToast(_ t: Toast?, seconds: Double = 9) {
        toastTask?.cancel()
        toast = t
        guard t != nil else { return }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    // MARK: Switching

    private func run(_ work: () async throws -> Void) async {
        errorMessage = nil
        do { try await work() } catch { errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong." }
        phaseText = nil
        await reload()
    }

    /// Hold-to-switch target: the selected account on the chosen tools.
    public func switchSelected() async {
        guard !busy, let a = selected else { return }
        let tools = Set(switchTools(for: a))
        guard !tools.isEmpty else { return }
        await switchAccount(a, tools: tools)
    }

    public func switchAccount(_ a: Account, tools: Set<Tool>) async {
        let previous = activeByTool
        busy = true
        showToast(nil)
        SoundPlayer.shared.play(.tick)
        errorMessage = nil
        var results: [(tool: Tool, result: Result<Void, Error>)] = []
        do {
            results = try await engine.switchGroup(a.id, tools: tools) { [weak self] tool, ph in
                Task { @MainActor in self?.phaseText = "\(tool.displayName): \(ph.userText)" }
            }
        } catch { errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong." }
        busy = false
        phaseText = nil
        await reload()
        let ok = results.filter { if case .success = $0.result { true } else { false } }.map(\.tool)
        let failed = results.compactMap { r -> (Tool, String)? in
            if case .failure(let e) = r.result { return (r.tool, (e as? LocalizedError)?.errorDescription ?? "Something went wrong.") }
            return nil
        }
        var prevForUndo: [Tool: UUID] = [:]
        for t in ok { if let p = previous[t] { prevForUndo[t] = p } }
        if failed.isEmpty, !ok.isEmpty {
            flashID = a.id; flashTick += 1
            SoundPlayer.shared.play(.success)
            showToast(Toast(message: "Switched \(ok.map(\.displayName).joined(separator: " + ")) to \(a.group.label)",
                            actions: prevForUndo.isEmpty ? [] : [.undo(prevForUndo)]))
            Task { await refreshUsage() }
        } else if !failed.isEmpty, !ok.isEmpty {
            flashID = a.id; flashTick += 1
            SoundPlayer.shared.play(.warn)
            var acts: [ToastAction] = failed.map { .retry($0.0, a.id) }
            if !prevForUndo.isEmpty { acts.append(.undo(prevForUndo)) }
            showToast(Toast(message: "\(ok.map(\.displayName).joined(separator: " + ")) switched. \(failed[0].0.displayName) couldn't switch: \(failed[0].1)",
                            actions: acts, isError: true), seconds: 20)
        } else if let f = failed.first {
            SoundPlayer.shared.play(.warn)
            showToast(Toast(message: "\(f.0.displayName) couldn't switch: \(f.1)", isError: true), seconds: 12)
        }
    }

    public func perform(_ action: ToastAction) async {
        showToast(nil)
        switch action {
        case .undo(let prev):
            SoundPlayer.shared.play(.tick)
            busy = true
            for tool in Tool.allCases { if let id = prev[tool] { try? await engine.switchTo(id) } }
            busy = false
            await reload()
            showToast(Toast(message: "Undone. Restored the previous accounts."), seconds: 4)
        case .retry(let tool, let gid):
            if let a = accounts.first(where: { $0.id == gid }) { await switchAccount(a, tools: [tool]) }
        }
    }

    // MARK: Account management

    public func rename(_ a: Account, to label: String) async {
        var g = a.group
        g.label = label
        await run { try await vault.updateGroup(g) }
        renamingID = nil
    }

    public func recolor(_ a: Account, to color: String) async {
        var g = a.group
        g.colorName = color
        await run { try await vault.updateGroup(g) }
    }

    /// Saves the live state of every tool that is currently on this account.
    public func recapture(_ a: Account) async {
        await run {
            for t in Tool.allCases where isActive(a, on: t) { if let p = a.profiles[t] { try await engine.recapture(profileID: p.id) } }
        }
        showToast(Toast(message: "Saved the current state to \(a.group.label)."), seconds: 4)
        SoundPlayer.shared.play(.success)
    }

    public func remove(_ a: Account) async {
        removingID = nil
        await run {
            for p in a.profiles.values { try await vault.remove(id: p.id) }
            for t in a.profiles.keys { await engine.reconcileActive(t) }
        }
        SoundPlayer.shared.play(.remove)
        showToast(Toast(message: "Removed \(a.group.label). Its sign-in stays in the app if it was active."), seconds: 6)
    }

    public func toggleReminder(_ a: Account) {
        var r = reminder(for: a.id)
        r.enabled.toggle()
        reminders[a.id] = r
        persistReminders()
        if r.enabled { Reminders.requestPermission() }
        Reminders.sync(group: a.id, label: a.group.label, prefs: r, snapshot: usage[a.id])
        SoundPlayer.shared.play(r.enabled ? .on : .off)
        showToast(Toast(message: r.enabled ? "You'll be notified when \(a.group.label) resets." : "Reminder off for \(a.group.label)."), seconds: 4)
    }

    public func setReminderWindow(_ a: Account, session: Bool? = nil, weekly: Bool? = nil) {
        var r = reminder(for: a.id)
        if let session { r.session = session }
        if let weekly { r.weekly = weekly }
        reminders[a.id] = r
        persistReminders()
        Reminders.sync(group: a.id, label: a.group.label, prefs: r, snapshot: usage[a.id])
        SoundPlayer.shared.play(.tick)
    }

    private func persistReminders() {
        let enc = Dictionary(uniqueKeysWithValues: reminders.map { ($0.key.uuidString, $0.value) })
        if let d = try? JSONEncoder().encode(enc) { UserDefaults.standard.set(d, forKey: "reminders") }
    }

    // MARK: Import / wizard

    public func openWizard(tool: Tool? = nil, group: UUID? = nil, reauth: Profile? = nil) {
        if let tool { wizardTool = tool }
        wizardGroupID = group
        reauthProfile = reauth
        showWizard = true
        onOpenWizard?()
    }

    public func importCurrent(tool: Tool, label: String, colorName: String, emoji: String?, groupID: UUID?) async -> Bool {
        var ok = false
        await run {
            let p = try await engine.importCurrent(tool: tool, label: label, colorName: colorName, emoji: emoji, groupID: groupID)
            selectedID = p.groupID
            ok = true
        }
        if ok { pendingEmptyTool = nil; SoundPlayer.shared.play(.success) }
        return ok
    }

    public func beginEmpty(tool: Tool) async -> Bool {
        var ok = false
        await run {
            try await engine.beginEmpty(tool: tool) { [weak self] ph in Task { @MainActor in self?.phaseText = ph.userText } }
            pendingEmptyTool = tool
            ok = true
        }
        return ok
    }

    /// Finishes re-authentication: stores the freshly signed-in state in the existing profile.
    public func finishReauth(_ p: Profile) async -> Bool {
        var ok = false
        await run {
            guard let live = try await engine.detectCurrent(p.tool) else { throw SwaplaneError.noCredentials(p.tool) }
            if let want = p.identityKey, let got = live.identityKey, want != got {
                throw SwaplaneError.io("That's a different account than \(p.label). Sign in with the same account, or add it as a new account.")
            }
            try await engine.recapture(profileID: p.id)
            try await vault.setActive(p.id, for: p.tool)
            ok = true
        }
        if ok { pendingEmptyTool = nil; reauthProfile = nil; SoundPlayer.shared.play(.success) }
        return ok
    }

    /// One-click welcome import: every detected, unsaved live account. Same identity across tools shares one account.
    public func importDetected() async {
        await run {
            var gid: UUID?
            var name = "Personal"
            if let d = unsaved(.claudeCode) ?? unsaved(.claudeDesktop) { name = Self.name(from: d.displayHint) }
            for tool in Tool.allCases {
                guard let d = unsaved(tool), probes[tool]?.status.allowsSwitching == true else { continue }
                if tool == .claudeDesktop, let key = d.identityKey,
                    let match = profiles.first(where: { $0.tool == .claudeCode && $0.identityKey == key })?.groupID
                { gid = match }
                let p = try await engine.importCurrent(tool: tool, label: name, colorName: "blue", groupID: gid)
                gid = p.groupID
                profiles = (try? await vault.profiles()) ?? profiles
            }
            selectedID = gid
        }
        SoundPlayer.shared.play(.success)
        showToast(Toast(message: "Imported your signed-in account."), seconds: 5)
    }

    static func name(from hint: String?) -> String {
        guard let hint, let at = hint.firstIndex(of: "@"), at != hint.startIndex else { return "Personal" }
        return String(hint[..<at]).prefix(1).uppercased() + String(hint[..<at]).dropFirst()
    }
}
