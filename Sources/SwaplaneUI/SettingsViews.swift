import ServiceManagement
import SwaplaneCore
import SwiftUI

/// Settings-only window (docs/DESIGN.md §7): native tabs. Account management lives in the panel.
struct SettingsView: View {
    @Bindable var model: AppModel

    private enum Pane: String, CaseIterable, Identifiable {
        case general = "General", safety = "Safety", tools = "Tools", activity = "Activity", about = "About"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .safety: "lock.shield"
            case .tools: "wrench.and.screwdriver"
            case .activity: "clock"
            case .about: "info.circle"
            }
        }
    }
    @State private var pane: Pane = .general

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Pane.allCases) { p in
                    Button { pane = p } label: {
                        VStack(spacing: 3) {
                            Image(systemName: p.symbol).font(.system(size: 17, weight: .regular)).frame(height: 20)
                            Text(p.rawValue).font(.system(size: 11, weight: pane == p ? .semibold : .regular))
                        }
                        .frame(width: 70, height: 48)
                        .foregroundStyle(pane == p ? Theme.signal : Color.secondary)
                        .background(pane == p ? Theme.signal.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(p.rawValue)
                    .accessibilityAddTraits(pane == p ? .isSelected : [])
                }
            }
            .padding(.top, 16).padding(.bottom, 8)
            Divider()
            Group {
                switch pane {
                case .general: GeneralTab(model: model)
                case .safety: SafetyTab(model: model)
                case .tools: ToolsTab(model: model)
                case .activity: ActivityTab(model: model)
                case .about: AboutTab()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 480, height: 508)
        .task { await model.reload() }
    }
}

private struct GeneralTab: View {
    @Bindable var model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Picker("Appearance", selection: $model.appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginError = nil }
                    catch { loginError = "Couldn't change the login item. Run the bundled app, not the development build."; launchAtLogin = !on }
                }
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.secondary) }
            Section("Feedback") {
                Toggle("Play sounds", isOn: $model.soundEnabled)
                Toggle("Reduce motion", isOn: $model.reduceMotionSetting)
                Text("AI Swaplane also follows the macOS Reduce Motion setting.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Usage") {
                Toggle("Show usage limits", isOn: $model.usageEnabled)
                Text("Reads the limits for the account Claude Code is signed in to, from Anthropic's servers. Nothing else leaves this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}

private struct SafetyTab: View {
    @Bindable var model: AppModel
    var body: some View {
        Form {
            Toggle("Mask email addresses", isOn: $model.maskEmails)
            Section("How your accounts are kept") {
                Text("Credentials are sealed with AES-256-GCM. The keys live in your Keychain. AI Swaplane never writes a token to disk in plain text, and it never refreshes tokens itself.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Switching needs a deliberate hold, so a stray click never changes your accounts.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button("Reveal data folder in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Paths().supportDir]) }
        }.formStyle(.grouped)
    }
}

private struct ToolsTab: View {
    @Bindable var model: AppModel
    var body: some View {
        Form {
            ForEach(Tool.allCases, id: \.self) { t in
                LabeledContent(t.displayName) { Text(statusText(model.probes[t])) }
            }
        }.formStyle(.grouped)
    }
    private func statusText(_ p: ToolProbe?) -> String {
        switch p?.status {
        case .ok?: "Ready" + (p?.version.map { " (\($0))" } ?? "")
        case .unverifiedVersion(let v)?: "Version \(v), not yet verified"
        case .notInstalled?: "Not installed"
        case .unsupported(let why)?: "Unsupported: \(why)"
        case nil: "Checking…"
        }
    }
}

private struct ActivityTab: View {
    @Bindable var model: AppModel
    var body: some View {
        if model.activity.isEmpty { ContentUnavailableView("No activity yet", systemImage: "clock") }
        else {
            Table(model.activity) {
                TableColumn("When") { Text($0.date.formatted(date: .abbreviated, time: .shortened)) }
                TableColumn("Tool") { Text($0.tool.displayName) }
                TableColumn("From → To") { Text("\($0.fromLabel ?? "—") → \($0.toLabel ?? "—")") }
                TableColumn("Result") { Text($0.result) }
            }
        }
    }
}

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 64)).foregroundStyle(Theme.signal)
            VStack(spacing: 8) {
                Text("AI Swaplane").font(.system(size: 34, weight: .bold))
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")").foregroundStyle(.secondary)
            }.padding(.top, 14)
            Text("Switch between AI accounts safely. No telemetry.")
                .font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 20)
            VStack(spacing: 8) {
                Text("Made by Ramy Sabry").font(.system(size: 13, weight: .medium))
                Text("Open source under the MIT License.").font(.system(size: 12)).foregroundStyle(.secondary)
                Link(destination: URL(string: "https://github.com/ramysabryali/ai-swaplane")!) {
                    Label("GitHub source", systemImage: "arrow.up.right").labelStyle(TrailingIconLabelStyle())
                        .font(.system(size: 12.5, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 7)
                        .overlay(Capsule().strokeBorder(Theme.line))
                }.buttonStyle(.plain).padding(.top, 10)
            }.padding(.top, 28)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Add / re-authenticate wizard (own small window)

struct ImportWizardView: View {
    @Bindable var model: AppModel
    var close: () -> Void
    @State private var tool: Tool = .claudeCode
    @State private var label = ""
    @State private var color = "blue"
    @State private var attach: UUID?
    @State private var busy = false

    private var detected: DetectedIdentity? { model.detected[tool] }
    private var installed: Bool { model.probes[tool]?.status.allowsSwitching ?? false }
    private var waiting: Bool { model.pendingEmptyTool == tool }
    private var reauth: Profile? { model.reauthProfile }
    private var existingMatch: Profile? {
        guard let key = detected?.identityKey else { return nil }
        return model.profiles.first { $0.tool == tool && $0.identityKey == key }
    }
    private var attachable: [Account] { model.accounts.filter { $0.profiles[tool] == nil } }

    private var title: String {
        if let r = reauth { return "Re-authenticate \(model.accounts.first { $0.id == r.groupID }?.group.label ?? r.label)" }
        return "Add an account"
    }
    private var subtitle: String {
        reauth != nil ? "Replace the saved sign-in for this account." : "Save a signed-in account so you can switch to it later."
    }
    private var canSave: Bool {
        if busy { return false }
        if reauth != nil { return waiting }
        let nameOK = attach != nil || !label.trimmingCharacters(in: .whitespaces).isEmpty
        return nameOK && (waiting || detected != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 20)).foregroundStyle(Theme.signal)
                    .frame(width: 42, height: 42).background(Theme.signal.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 17, weight: .semibold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 14)
            Divider()
            Form {
                if reauth == nil {
                    Picker("Tool", selection: $tool) { ForEach(Tool.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                        .pickerStyle(.segmented).disabled(waiting)
                }
                Section("Sign-in") {
                    if waiting {
                        Label("\(tool.displayName) is signed out. Sign in with \(reauth != nil ? "the same account" : "the other account"), then click Save.",
                              systemImage: "person.badge.key").foregroundStyle(Theme.signal)
                    } else if reauth != nil {
                        Text("AI Swaplane signs \(tool.displayName) out, you sign in again, and the new sign-in replaces the saved one for this account.")
                            .foregroundStyle(.secondary)
                    } else if !installed {
                        Text("\(tool.displayName) isn't installed on this Mac.").foregroundStyle(.secondary)
                    } else if let d = detected {
                        LabeledContent("Currently signed in", value: model.display(d.displayHint) ?? "Signed in (email unknown)")
                        if let o = d.organization { LabeledContent("Organisation", value: o) }
                    } else {
                        Text("Not signed in to \(tool.displayName).").foregroundStyle(.secondary)
                    }
                    if !waiting {
                        Button(reauth != nil ? "Sign out and sign in again…" : "Sign in with another account…") {
                            busy = true
                            Task { _ = await model.beginEmpty(tool: tool); busy = false }
                        }.disabled(!installed || busy)
                    }
                }
                if reauth == nil {
                    Section("Account") {
                        Picker("Save as", selection: $attach) {
                            Text("New account").tag(UUID?.none)
                            ForEach(attachable) { Text("Add to \($0.group.label)").tag(UUID?.some($0.id)) }
                        }
                        if attach == nil {
                            TextField("Name", text: $label, prompt: Text("For example Work"))
                            Picker("Colour", selection: $color) { ForEach(Palette.names, id: \.self) { Text($0.capitalized).tag($0) } }
                        }
                        if !waiting, let m = existingMatch {
                            Label("Already saved as “\(m.label)”. Importing again creates a separate account with its own state.",
                                  systemImage: "info.circle").font(.caption).foregroundStyle(Theme.warn)
                        }
                    }
                }
                Text("Saved to your Keychain-protected vault, encrypted on disk. Nothing is uploaded.")
                    .font(.caption).foregroundStyle(.secondary)
                if let e = model.errorMessage { Text(e).font(.caption).foregroundStyle(Theme.danger) }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { model.pendingEmptyTool = nil; model.reauthProfile = nil; close() }
                    .controlSize(.large)
                Button(waiting || reauth != nil ? "Save" : "Import") {
                    busy = true
                    Task {
                        let ok: Bool
                        if let r = reauth { ok = await model.finishReauth(r) }
                        else {
                            ok = await model.importCurrent(
                                tool: tool, label: attach.flatMap { id in model.accounts.first { $0.id == id }?.group.label } ?? label.trimmingCharacters(in: .whitespaces),
                                colorName: color, emoji: nil, groupID: attach)
                        }
                        busy = false
                        if ok { close() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent).tint(Theme.signal).controlSize(.large)
                .disabled(!canSave)
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
        }
        .frame(width: 480, height: reauth != nil ? 470 : 658)
        .onAppear {
            model.errorMessage = nil
            if let r = reauth { tool = r.tool } else { tool = model.wizardTool }
            attach = model.wizardGroupID
            if attach == nil, let key = detected?.identityKey {
                attach = model.profiles.first { $0.tool != tool && $0.identityKey == key }.flatMap { p in attachable.first { $0.id == p.groupID }?.id }
            }
        }
        .onChange(of: tool) { attach = nil }
        .task { await model.reload() }
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.title; configuration.icon.font(.system(size: 10, weight: .bold)) }
    }
}
