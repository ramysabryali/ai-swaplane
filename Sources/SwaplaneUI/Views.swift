import ServiceManagement
import SwaplaneCore
import SwiftUI

enum Palette {
    static let names = ["blue", "purple", "pink", "red", "orange", "yellow", "green", "teal"]
    static func color(_ name: String) -> Color {
        switch name {
        case "purple": .purple
        case "pink": .pink
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "teal": .teal
        default: .blue
        }
    }
}

struct ProfileBadge: View {
    let profile: Profile
    var body: some View {
        ZStack {
            Circle().fill(Palette.color(profile.colorName).opacity(0.9))
            if let e = profile.emoji, !e.isEmpty { Text(e).font(.system(size: 14)) }
            else { Text(String(profile.label.prefix(1)).uppercased()).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white) }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

struct ProfileRow: View {
    @Bindable var model: AppModel
    let profile: Profile

    var body: some View {
        let active = model.isActive(profile)
        Button {
            Task { await model.switchTo(profile) }
        } label: {
            HStack(spacing: 10) {
                ProfileBadge(profile: profile)
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.label).font(.body.weight(active ? .semibold : .regular))
                    if let hint = model.display(profile.identityHint) {
                        Text(hint).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if active { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityLabel("Active") }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4).padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .disabled(model.switchingTool != nil)
        .background(active ? Color.accentColor.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("\(profile.label), \(profile.tool.displayName)\(active ? ", active" : "")")
        .contextMenu {
            Button("Re-import current state") { Task { await model.recapture(profile) } }
            Button("Open Swaplane…") { model.onOpenMainWindow?() }
        }
    }
}

struct PopoverView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Swaplane").font(.headline)
                Spacer()
                Button { model.openWizard() } label: { Image(systemName: "plus") }
                    .help("Add profile").accessibilityLabel("Add profile")
                Button { model.onOpenMainWindow?() } label: { Image(systemName: "gearshape") }
                    .help("Open Swaplane").accessibilityLabel("Open Swaplane")
            }
            .buttonStyle(.borderless).padding(12)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Tool.allCases, id: \.self) { tool in section(tool) }
                }.padding(12)
            }.frame(maxHeight: 380)

            if let phase = model.phase {
                Divider()
                HStack { ProgressView().controlSize(.small); Text(phase.userText).font(.caption) }.padding(10)
            }
            if let err = model.errorMessage {
                Divider()
                Text(err).font(.caption).foregroundStyle(.red).padding(10).fixedSize(horizontal: false, vertical: true)
            }
            if let toast = model.toast {
                Divider()
                HStack {
                    Text(toast.message).font(.caption)
                    Spacer()
                    if toast.undoProfileID != nil { Button("Undo") { Task { await model.undo(toast) } }.buttonStyle(.link) }
                }.padding(10)
            }
            Divider()
            HStack {
                Button("Open Swaplane…") { model.onOpenMainWindow?() }
                Spacer()
                Button("Quit") { model.onQuit?() }
            }.buttonStyle(.borderless).padding(10)
        }
        .frame(width: 340)
        .task { await model.reload() }
    }

    @ViewBuilder private func section(_ tool: Tool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(tool.displayName, systemImage: tool.symbolName)
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            let status = model.probes[tool]?.status
            if status == .notInstalled {
                Text("\(tool.displayName) isn't installed.").font(.caption).foregroundStyle(.secondary)
            } else {
                if case .unverifiedVersion(let v)? = status {
                    Text("Version \(v) hasn't been verified yet.").font(.caption2).foregroundStyle(.orange)
                }
                if model.drift.contains(tool) {
                    Label("Signed in to a different account than the active profile.", systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(.orange)
                }
                let list = model.profiles(for: tool)
                if list.isEmpty {
                    Button("Import current \(tool.displayName) account") { model.openWizard(tool) }
                        .buttonStyle(.link).font(.caption)
                }
                ForEach(list) { ProfileRow(model: model, profile: $0) }
            }
        }
    }
}

// MARK: Main window

enum SidebarItem: String, CaseIterable, Identifiable {
    case profiles = "Profiles", activity = "Activity", settings = "Settings"
    var id: String { rawValue }
    var symbol: String { self == .profiles ? "person.2" : self == .activity ? "clock" : "gearshape" }
}

struct MainWindowView: View {
    @Bindable var model: AppModel
    @State private var selection: SidebarItem? = .profiles

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                .navigationSplitViewColumnWidth(min: 150, ideal: 170)
        } detail: {
            switch selection ?? .profiles {
            case .profiles: ProfilesView(model: model)
            case .activity: ActivityView(model: model)
            case .settings: SettingsView(model: model)
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .sheet(isPresented: $model.showWizard) { ImportWizardView(model: model) }
        .task { await model.reload() }
    }
}

struct ProfilesView: View {
    @Bindable var model: AppModel
    @State private var editing: Profile?
    @State private var removing: Profile?

    var body: some View {
        List {
            ForEach(Tool.allCases, id: \.self) { tool in
                Section(tool.displayName) {
                    let list = model.profiles(for: tool)
                    if list.isEmpty { Text("No profiles yet").foregroundStyle(.secondary) }
                    ForEach(list) { p in
                        HStack {
                            ProfileBadge(profile: p)
                            VStack(alignment: .leading) {
                                Text(p.label)
                                Text([model.display(p.identityHint), p.lastUsedAt.map { "Last used " + $0.formatted(.relative(presentation: .named)) }]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.isActive(p) { Text("Active").font(.caption).foregroundStyle(.tint) }
                            else { Button("Switch") { Task { await model.switchTo(p) } }.disabled(model.switchingTool != nil) }
                            Menu {
                                Button("Rename / recolor…") { editing = p }
                                Button("Re-import current state") { Task { await model.recapture(p) } }
                                Divider()
                                Button("Remove…", role: .destructive) { removing = p }
                            } label: { Image(systemName: "ellipsis.circle") }
                                .menuStyle(.borderlessButton).fixedSize()
                        }
                    }
                }
            }
        }
        .toolbar { Button { model.openWizard() } label: { Label("Add profile", systemImage: "plus") } }
        .overlay(alignment: .bottom) {
            if let e = model.errorMessage { Text(e).padding(8).background(.red.opacity(0.15), in: Capsule()).padding() }
        }
        .sheet(item: $editing) { p in EditProfileView(model: model, profile: p) }
        .confirmationDialog("Remove “\(removing?.label ?? "")”?", isPresented: .constant(removing != nil), presenting: removing) { p in
            Button("Remove and delete saved data", role: .destructive) { Task { await model.remove(p); removing = nil } }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: { _ in Text("The saved snapshot and its encryption key are deleted. The signed-in account itself is not affected.") }
    }
}

struct EditProfileView: View {
    @Bindable var model: AppModel
    let profile: Profile
    @State private var label = ""
    @State private var color = "blue"
    @State private var emoji = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            TextField("Name", text: $label)
            TextField("Emoji (optional)", text: $emoji)
            Picker("Color", selection: $color) { ForEach(Palette.names, id: \.self) { n in Label(n.capitalized, systemImage: "circle.fill").foregroundStyle(Palette.color(n)).tag(n) } }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") {
                Task { await model.rename(profile, to: label, colorName: color, emoji: emoji.isEmpty ? nil : String(emoji.prefix(2))); dismiss() }
            }.disabled(label.trimmingCharacters(in: .whitespaces).isEmpty).keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(width: 380)
        .onAppear { label = profile.label; color = profile.colorName; emoji = profile.emoji ?? "" }
    }
}

struct ActivityView: View {
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

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginError = nil }
                        catch { loginError = "Couldn't change login item (run the bundled app, not the dev build)."; launchAtLogin = !on }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.secondary) }
                Toggle("Mask emails in the UI", isOn: $model.maskEmails)
            }
            Section("Tools") {
                ForEach(Tool.allCases, id: \.self) { tool in
                    LabeledContent(tool.displayName) { Text(statusText(model.probes[tool])) }
                }
            }
            Section("Data") {
                Text("Credentials are sealed with AES-256-GCM; the keys live in your Keychain. Nothing leaves this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Reveal data folder in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Paths().supportDir])
                }
            }
        }.formStyle(.grouped)
    }

    private func statusText(_ p: ToolProbe?) -> String {
        switch p?.status {
        case .ok?: "Ready" + (p?.version.map { " (\($0))" } ?? "")
        case .unverifiedVersion(let v)?: "Version \(v) — not yet verified"
        case .notInstalled?: "Not installed"
        case .unsupported(let why)?: "Unsupported: \(why)"
        case nil: "Checking…"
        }
    }
}

// MARK: Import wizard

struct ImportWizardView: View {
    @Bindable var model: AppModel
    @State private var tool: Tool = .claudeCode
    @State private var label = ""
    @State private var color = "blue"
    @State private var emoji = ""
    @State private var busy = false
    @Environment(\.dismiss) private var dismiss

    private var detected: DetectedIdentity? { model.detected[tool] }
    private var installed: Bool { model.probes[tool]?.status.allowsSwitching ?? false }
    private var waitingForSignIn: Bool { model.pendingEmptyTool == tool }
    /// A saved profile for this tool that already holds the live account.
    private var existingMatch: Profile? {
        guard let key = detected?.identityKey else { return nil }
        return model.profiles(for: tool).first { $0.identityKey == key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a profile").font(.title2.bold())
            Picker("Tool", selection: $tool) { ForEach(Tool.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                .pickerStyle(.segmented).disabled(waitingForSignIn)

            if waitingForSignIn {
                Label("\(tool.displayName) is signed out. Sign in with the other account, then click Save.", systemImage: "person.badge.key")
                    .padding(10).background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
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

            TextField("Profile name (e.g. Work)", text: $label)
            HStack {
                TextField("Emoji (optional)", text: $emoji).frame(width: 140)
                Picker("Color", selection: $color) { ForEach(Palette.names, id: \.self) { Text($0.capitalized).tag($0) } }
            }
            if !waitingForSignIn, let m = existingMatch {
                Label("This account is already saved as “\(m.label)”. Importing again creates a separate profile with its own state.",
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text("Saved to your Keychain-protected vault, encrypted on disk. Nothing is uploaded.")
                .font(.caption).foregroundStyle(.secondary)
            if let e = model.errorMessage { Text(e).font(.caption).foregroundStyle(.red) }

            HStack {
                if !waitingForSignIn {
                    Button("Sign in with another account…") {
                        busy = true
                        Task { _ = await model.beginEmpty(tool: tool); busy = false }
                    }.disabled(!installed || busy)
                }
                Spacer()
                Button("Cancel") { model.pendingEmptyTool = nil; dismiss() }
                Button(waitingForSignIn ? "Save" : "Import") {
                    busy = true
                    Task {
                        let ok = await model.importCurrent(
                            tool: tool, label: label.trimmingCharacters(in: .whitespaces),
                            colorName: color, emoji: emoji.isEmpty ? nil : String(emoji.prefix(2)))
                        busy = false
                        if ok { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty || busy || (!waitingForSignIn && detected == nil))
            }
        }
        .padding(22).frame(width: 460)
        .onAppear { tool = model.wizardTool }
        .task { await model.reload() }
    }
}
