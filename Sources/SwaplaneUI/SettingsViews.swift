import ServiceManagement
import SwaplaneCore
import SwiftUI

/// Settings-only window (docs/DESIGN.md §7): native tabs. Account management lives in the panel.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            GeneralTab(model: model).tabItem { Label("General", systemImage: "gearshape") }
            SafetyTab(model: model).tabItem { Label("Safety", systemImage: "lock.shield") }
            ToolsTab(model: model).tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
            ActivityTab(model: model).tabItem { Label("Activity", systemImage: "clock") }
            AboutTab().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 380)
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
                Text("Swaplane also follows the macOS Reduce Motion setting.").font(.caption).foregroundStyle(.secondary)
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
                Text("Credentials are sealed with AES-256-GCM. The keys live in your Keychain. Swaplane never writes a token to disk in plain text, and it never refreshes tokens itself.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Switching needs a deliberate hold, and every switch can be undone for a few seconds.")
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
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 34)).foregroundStyle(Theme.signal)
            Text("Swaplane").font(.title2.bold())
            Text("Version 0.2 (development)").foregroundStyle(.secondary)
            Text("Switch between AI accounts safely. No telemetry.").font(.callout).foregroundStyle(.secondary)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(reauth != nil ? "Re-authenticate \(model.accounts.first { $0.id == reauth?.groupID }?.group.label ?? reauth!.label)" : "Add an account")
                .font(.title2.bold())
            if reauth == nil {
                Picker("Tool", selection: $tool) { ForEach(Tool.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                    .pickerStyle(.segmented).disabled(waiting)
            }
            if waiting {
                Label("\(tool.displayName) is signed out. Sign in with \(reauth != nil ? "the same account" : "the other account"), then click Save.",
                      systemImage: "person.badge.key")
                    .padding(10).background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            } else if reauth != nil {
                Text("Swaplane signs \(tool.displayName) out, you sign in again, and the new sign-in replaces the saved one for this account.")
                    .foregroundStyle(.secondary)
            } else if !installed {
                Text("\(tool.displayName) isn't installed on this Mac.").foregroundStyle(.secondary)
            } else if let d = detected {
                GroupBox("Currently signed in") {
                    VStack(alignment: .leading) {
                        Text(model.display(d.displayHint) ?? "Signed in (email unknown)")
                        if let o = d.organization { Text(o).font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("Not signed in to \(tool.displayName).").foregroundStyle(.secondary)
            }

            if reauth == nil {
                Picker("Account", selection: $attach) {
                    Text("New account").tag(UUID?.none)
                    ForEach(attachable) { Text("Add to \($0.group.label)").tag(UUID?.some($0.id)) }
                }
                if attach == nil {
                    TextField("Name (for example Work)", text: $label)
                    Picker("Colour", selection: $color) { ForEach(Palette.names, id: \.self) { Text($0.capitalized).tag($0) } }
                }
                if !waiting, let m = existingMatch {
                    Label("This account is already saved as “\(m.label)”. Importing again creates a separate account with its own state.",
                          systemImage: "info.circle").font(.caption).foregroundStyle(.orange)
                }
            }
            Text("Saved to your Keychain-protected vault, encrypted on disk. Nothing is uploaded.")
                .font(.caption).foregroundStyle(.secondary)
            if let e = model.errorMessage { Text(e).font(.caption).foregroundStyle(.red) }

            HStack {
                if !waiting {
                    Button(reauth != nil ? "Sign out and sign in again…" : "Sign in with another account…") {
                        busy = true
                        Task { _ = await model.beginEmpty(tool: tool); busy = false }
                    }.disabled(!installed || busy)
                }
                Spacer()
                Button("Cancel") { model.pendingEmptyTool = nil; model.reauthProfile = nil; close() }
                Button(waiting ? "Save" : reauth != nil ? "Save" : "Import") {
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
                .disabled(busy || (reauth != nil ? !waiting : ((attach == nil && label.trimmingCharacters(in: .whitespaces).isEmpty) || (!waiting && detected == nil))))
            }
        }
        .padding(22).frame(width: 460)
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
