import AppKit
import SwaplaneCore
import SwiftUI

/// Chooses between the guided "Sign in to a new account" window and the older re-authenticate / attach window.
struct WizardRouter: View {
    @Bindable var model: AppModel
    var close: () -> Void
    var body: some View {
        if model.newAccount != nil { NewAccountView(model: model, close: close) }
        else { ImportWizardView(model: model, close: close) }
    }
}

/// Header shared by the guided windows: icon tile, title and a step line.
private struct WindowHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
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
    }
}

private struct InfoRow: View {
    let symbol: String
    let title: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(Theme.signal).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// "Sign in to a new account": prepare, sign in elsewhere (detected automatically), import.
struct NewAccountView: View {
    @Bindable var model: AppModel
    var close: () -> Void
    @State private var name = ""
    @State private var color = "blue"
    @State private var skipImport = false
    @State private var importing = false

    private var phase: NewAccountFlow.Phase { model.newAccount?.phase ?? .intro }
    private var found: DetectedAccount? { phase == .signIn ? model.newAccountCandidate : nil }
    private var unsavedLive: [DetectedAccount] { model.detectedAccounts }
    private var previousLabel: String? {
        model.newAccount?.previous.values.compactMap { id in
            model.profiles.first { $0.id == id }.flatMap { p in model.groups.first { $0.id == p.groupID }?.label }
        }.first
    }

    /// The account that is signed in right now, for the sign-out disclaimer.
    private var currentAccountName: String {
        model.display(model.detected[.claudeCode]?.displayHint ?? model.detected[.claudeDesktop]?.displayHint)
            ?? previousLabel ?? model.activeAccount(for: .claudeCode)?.group.label ?? model.activeAccount(for: .claudeDesktop)?.group.label
            ?? "your current account"
    }

    private var subtitle: String {
        switch phase {
        case .intro: "Step 1 of 3 · Prepare"
        case .preparing: "Step 1 of 3 · Preparing"
        case .signIn: found == nil ? "Step 2 of 3 · Sign in" : "Step 3 of 3 · Import"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            WindowHeader(title: "Sign in to a new account", subtitle: subtitle)
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                switch phase {
                case .intro: intro
                case .preparing: preparing
                case .signIn: if let f = found { foundView(f) } else { signIn }
                }
                if let e = model.errorMessage { Text(e).font(.caption).foregroundStyle(Theme.danger) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22).padding(.vertical, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer
        }
        .frame(width: 480, height: 570)
        .onAppear { model.errorMessage = nil; color = model.nextColor() }
        .task { await model.reload() }
        .task(id: phase) {
            // Look for the new sign-in while the window waits for it.
            while phase == .signIn, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if phase == .signIn { await model.reload() }
            }
        }
        .onChange(of: found?.id) { _, id in
            if id != nil, let f = found { name = AppModel.name(from: f.email); color = model.nextColor() }
        }
    }

    // MARK: Steps

    @ViewBuilder private var intro: some View {
        if !unsavedLive.isEmpty && !skipImport {
            VStack(alignment: .leading, spacing: 10) {
                Label("Import your current account first", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.warn)
                Text("\(model.display(unsavedLive[0].email) ?? "The account signed in now") isn't saved in AI Swaplane yet. Signing in to a new account clears it from this Mac.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("Import it first") { Task { for a in unsavedLive { _ = await model.importDetected(a, quiet: true) } } }
                        .buttonStyle(.borderedProminent).tint(Theme.signal).disabled(model.busy)
                    Button("Continue without importing") { skipImport = true }.buttonStyle(.plain)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warn.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
        VStack(alignment: .leading, spacing: 6) {
            Label("Disclaimer", systemImage: "info.circle.fill").font(.system(size: 12.5, weight: .semibold))
            Text("Automatic detection is running. Accounts that are already signed in on this Mac are found and offered for import by themselves. Use this only to sign in to a totally new account that isn't signed in on this Mac.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
        Label("Signing in to a new account signs you out of \(currentAccountName) on this Mac. It stays saved in AI Swaplane, so you can switch back any time.",
              systemImage: "person.crop.circle.badge.minus")
            .font(.system(size: 12.5, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.signal.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.signal.opacity(0.35)))
        InfoRow(symbol: "person.crop.circle.badge.minus", title: "We clear the sign-in on this Mac",
                text: "Claude Desktop returns to its sign-in screen. Claude Code switches when you run /login. You stay signed in to Claude online.")
        InfoRow(symbol: "person.crop.circle.badge.plus", title: "You sign in as the new account",
                text: "We notice it automatically, then you import it.")
    }

    private var preparing: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(model.phaseText ?? "Saving your current account…").font(.system(size: 13))
        }
    }

    private var signIn: some View {
        VStack(alignment: .leading, spacing: 14) {
            InfoRow(symbol: "checkmark.circle", title: "\(previousLabel ?? "Your account") is saved",
                    text: "You're signed out of it on this Mac. Sign in as the new account with either tool, or both.")
            HStack(spacing: 8) {
                Button { openDesktop() } label: { Label("Open Claude Desktop", systemImage: "macwindow") }
                Button { model.openTerminal() } label: { Label("Open Terminal", systemImage: "terminal") }
            }
            Text("In Terminal, run  claude  then  /login").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
            if let saved = model.signedInAsSavedAccount {
                Label("You're signed in as \(saved.group.label), which is already saved. Sign in as a different account to add a new one, or cancel to keep \(saved.group.label).",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.warn.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            }
            Divider()
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Waiting for the new sign-in…").font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            Text("Automatic detection is running. This window updates when the new account signs in.").font(.system(size: 11.5)).foregroundStyle(.tertiary)
        }
    }

    private func foundView(_ f: DetectedAccount) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Found \(model.display(f.email) ?? "a new account")").font(.system(size: 14, weight: .semibold))
                    Text(f.tools.map { "\($0.shortName) ✓" }.joined(separator: "   "))
                        .font(.system(size: 12)).foregroundStyle(Theme.success)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    Text("Name").foregroundStyle(.secondary)
                    TextField("Name", text: $name, prompt: Text("For example Work")).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Colour").foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(Palette.names, id: \.self) { n in
                            Circle().fill(Palette.color(n)).frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(color == n ? 0.9 : 0), lineWidth: 2).padding(-3))
                                .onTapGesture { color = n }
                        }
                    }
                }
            }.font(.system(size: 13))
            Text("Saved to your Keychain-protected vault, encrypted on disk. Nothing is uploaded.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            if phase == .signIn, let l = previousLabel {
                Text("Changed your mind? Cancel restores \(l).").font(.system(size: 11.5)).foregroundStyle(.tertiary)
            }
            Spacer()
            Button(phase == .signIn ? "Cancel and restore" : "Cancel") {
                Task { await model.cancelNewAccount(); close() }
            }.controlSize(.large).disabled(phase == .preparing)
            switch phase {
            case .intro:
                Button("Continue") { Task { await model.prepareNewAccount() } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Theme.signal).controlSize(.large)
                    .disabled(model.busy || (!unsavedLive.isEmpty && !skipImport))
            case .preparing:
                EmptyView()
            case .signIn:
                Button("Import account") {
                    importing = true
                    Task { let ok = await model.finishNewAccount(name: name, color: color); importing = false; if ok { close() } }
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Theme.signal).controlSize(.large)
                .disabled(found == nil || importing || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
    }

    private func openDesktop() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
