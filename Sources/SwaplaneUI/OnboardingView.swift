import AppKit
import ServiceManagement
import SwaplaneCore
import SwiftUI

/// First-run tour: find the menu bar icon, allow Keychain access, import signed-in accounts, learn how switching works, open at login.
/// Signing in to a new account is deliberately left to the panel's + menu.
struct OnboardingView: View {
    @Bindable var model: AppModel
    var close: () -> Void
    @State private var page: Int
    /// True only while the first real detection pass runs when the import screen opens.
    @State private var detecting = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    @State private var loginError: String?
    @State private var revertingLogin = false

    init(model: AppModel, page: Int = 0, detecting: Bool = true, close: @escaping () -> Void) {
        self.model = model
        self.close = close
        _page = State(initialValue: page)
        _detecting = State(initialValue: detecting)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: findIt
                case 1: keychainStep
                case 2: importStep
                case 3: switchStep
                default: loginStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 28).padding(.top, 28)
            Divider()
            HStack {
                Button("Skip") { model.finishOnboarding(); close() }.buttonStyle(.plain).foregroundStyle(.secondary)
                    .opacity(page == 4 ? 0 : 1)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { Circle().fill(page == $0 ? Theme.signal : Color.primary.opacity(0.2)).frame(width: 6, height: 6) }
                }
                Spacer()
                if page > 0 { Button("Back") { page -= 1 }.controlSize(.large) }
                Button(page == 4 ? "Open the panel" : "Next") {
                    if page == 4 { model.finishOnboarding(openPanel: true); close() } else { page += 1 }
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Theme.signal).controlSize(.large)
                .disabled(page == 1 && model.keychainAccess == .denied)
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
        }
        .frame(width: 480, height: 540)
        .task(id: page) {
            guard page == 2 else { return }
            detecting = true
            await model.reload()
            detecting = false
            // Detection keeps running quietly while this screen is open.
            while page == 2, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard page == 2 else { break }
                await model.reload()
            }
        }
    }

    // MARK: 1. Find it

    private var findIt: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 34)).foregroundStyle(Theme.signal)
            Text("Find AI Swaplane in your menu bar").font(.system(size: 19, weight: .semibold))
            Text("Look for the fork icon with two small bars at the top right of your screen. The bars show your session and weekly usage. Click it to open the panel.")
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                Spacer()
                Text("Wi-Fi").font(.system(size: 11.5)).foregroundStyle(.secondary)
                Text(Date.now.formatted(date: .omitted, time: .shortened)).font(.system(size: 11.5)).foregroundStyle(.secondary)
                Image(nsImage: MenuBarIcon.image(primary: nil, secondary: nil, session: 40, weekly: 15))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.signal, lineWidth: 2))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .padding(.top, 6)
            Text("Can't see it? Make room in the menu bar by closing other menu bar apps.")
                .font(.system(size: 11.5)).foregroundStyle(.tertiary)
        }
    }

    // MARK: 2. Keychain access

    private var keychainStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Allow Keychain access").font(.system(size: 19, weight: .semibold))
            Text("Claude Code keeps its sign-in in your Keychain. AI Swaplane reads it to import accounts and show usage. It never leaves your Mac.")
                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            // What macOS will show, so the choice is easy to recognise.
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "key.fill").font(.system(size: 20)).foregroundStyle(.secondary)
                    Text("“AI Swaplane” wants to use confidential information stored in “Claude Code-credentials” in your keychain.")
                        .font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Spacer()
                    Text("Deny").padding(.horizontal, 12).padding(.vertical, 4).background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    Text("Allow").padding(.horizontal, 12).padding(.vertical, 4).background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    Text("Always Allow").fontWeight(.semibold).padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Theme.signal.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.signal, lineWidth: 2))
                }.font(.system(size: 11.5))
            }
            .padding(12).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
            Label("Choose Always Allow. Otherwise macOS asks again every time AI Swaplane checks your usage or switches accounts.",
                  systemImage: "hand.point.up.left").font(.system(size: 12.5, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button { Task { await model.requestKeychainAccess() } } label: {
                    Text(model.keychainAccess == nil ? "Allow access" : "Ask again")
                }
                .buttonStyle(.borderedProminent).tint(Theme.signal).disabled(model.requestingKeychain)
                if model.requestingKeychain { ProgressView().controlSize(.small) }
                switch model.keychainAccess {
                case .granted?: Label("Access granted", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success).font(.system(size: 12.5))
                case .notSignedIn?: Text("No Claude Code sign-in found yet. macOS will ask the first time you import one.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                case .denied?: Label("Access denied", systemImage: "xmark.octagon.fill").foregroundStyle(Theme.danger).font(.system(size: 12.5, weight: .medium))
                case nil: EmptyView()
                }
            }
            if model.keychainAccess == .denied { deniedDisclaimer }
        }
    }

    private var deniedDisclaimer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Disclaimer: Keychain access is required", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.warn)
            Text("AI Swaplane can't import or switch your accounts without reading your Claude Code sign-in from the Keychain. Choose **Ask again**, then **Always Allow**.")
                .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Text("It is secure. macOS controls this access and you can remove it any time in Keychain Access. Your sign-in stays on this Mac, saved copies are encrypted with a key held in your Keychain, and nothing is uploaded.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warn.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.warn.opacity(0.35)))
    }

    // MARK: 3. Import

    private var importStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import your accounts").font(.system(size: 19, weight: .semibold))
            Text("AI Swaplane looks for accounts that are already signed in on this Mac.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            VStack(spacing: 8) {
                if detecting {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Looking for signed-in accounts…").font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .padding(12).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    ForEach(model.accounts) { a in
                        row(email: model.display(a.identityHint) ?? a.group.label, tools: a.tools, imported: true) {}
                    }
                    ForEach(model.detectedAccounts) { d in
                        row(email: model.display(d.email) ?? "Signed-in account", tools: d.tools, imported: false) { Task { await model.importDetected(d) } }
                    }
                    if model.accounts.isEmpty && model.detectedAccounts.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No signed-in account found yet").font(.system(size: 13, weight: .semibold))
                            Text("Sign in to Claude Desktop or run  claude  in Terminal. It shows up here by itself.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                }
            }
            if model.detectedAccounts.count > 1 {
                Button("Import all accounts") { Task { await model.importAllDetected() } }.controlSize(.regular)
            }
            if !detecting { toolStatus }
            Label("Automatic detection stays on. Whenever you sign in to Claude on this Mac, AI Swaplane notices and offers to import it. It only reads the sign-in on this Mac and never sends it anywhere.",
                  systemImage: "dot.radiowaves.left.and.right")
                .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    /// What the detection pass found per tool, from the real result.
    private var toolStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Tool.allCases, id: \.self) { t in
                HStack(spacing: 6) {
                    Image(systemName: statusSymbol(t)).font(.system(size: 11)).frame(width: 14)
                        .foregroundStyle(model.detected[t] != nil ? Theme.success : Color.secondary)
                    Text("\(t.displayName): \(statusText(t))")
                }
            }
        }
        .font(.system(size: 11.5)).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func statusSymbol(_ t: Tool) -> String { model.detected[t] != nil ? "checkmark.circle.fill" : "circle.dashed" }
    private func statusText(_ t: Tool) -> String {
        if model.probes[t]?.status == .notInstalled { return "not installed" }
        guard let d = model.detected[t] else { return "not signed in" }
        return "signed in" + (model.display(d.displayHint).map { " as \($0)" } ?? "")
    }

    private func row(email: String, tools: [Tool], imported: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: imported ? "checkmark.circle.fill" : "person.crop.circle").font(.system(size: 18))
                .foregroundStyle(imported ? Theme.success : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(email).font(.system(size: 13, weight: .semibold))
                Text(tools.map(\.shortName).joined(separator: " and ")).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            if imported { Text("Imported").font(.system(size: 12)).foregroundStyle(Theme.success) }
            else {
                Button("Import account", action: action).buttonStyle(.borderedProminent).tint(Theme.signal).disabled(model.busy)
            }
        }
        .padding(10).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: 4. Switching (information only)

    private var switchStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How switching works").font(.system(size: 19, weight: .semibold))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06))
                GeometryReader { g in RoundedRectangle(cornerRadius: 9).fill(Theme.signal.opacity(0.35)).frame(width: g.size.width * 0.55) }
                Text("Hold to switch to Work").font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity)
            }
            .frame(height: 38).clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.line))
            .accessibilityHidden(true)
            Text("An illustration. You'll use the real button in the panel once you have a second account.")
                .font(.system(size: 11.5)).foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 12) {
                step("1", "Hold the button", "Hold it until it fills. A quick tap does nothing, so you can't switch by accident.")
                step("2", "We swap the sign-in", "AI Swaplane saves your current account, quits Claude Desktop, swaps in the other sign-in and reopens it. The CLI uses the new account the next time you run claude.")
                step("3", "Nothing is lost", "If a step fails, your previous account is restored automatically.")
            }
        }
    }

    private func step(_ n: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n).font(.system(size: 12, weight: .semibold)).frame(width: 22, height: 22)
                .background(Theme.signal.opacity(0.18), in: Circle()).foregroundStyle(Theme.signal)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 5. Open at login

    private var loginStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Open at login").font(.system(size: 19, weight: .semibold))
            Text("AI Swaplane lives in your menu bar. Opening it at login keeps the icon there, keeps your usage numbers fresh, and lets reset reminders arrive.")
                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Image(systemName: "power").font(.system(size: 18)).foregroundStyle(Theme.signal).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open AI Swaplane at login").font(.system(size: 13, weight: .semibold))
                    Text("Recommended").font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Open AI Swaplane at login", isOn: $launchAtLogin).labelsHidden().toggleStyle(.switch).tint(Theme.signal)
                    .onChange(of: launchAtLogin) { _, on in setLogin(on) }
            }
            .padding(12).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            if loginNeedsApproval {
                VStack(alignment: .leading, spacing: 8) {
                    Text("macOS needs your approval. Turn on AI Swaplane in System Settings > General > Login Items.")
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Button("Open Login Items settings") { SMAppService.openSystemSettingsLoginItems() }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.warn.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            }
            if let loginError { Text(loginError).font(.system(size: 12)).foregroundStyle(Theme.warn) }
            Text("You can change this any time in Settings > General. Quit from the panel stops AI Swaplane until the next login.")
                .font(.system(size: 11.5)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func setLogin(_ on: Bool) {
        if revertingLogin { revertingLogin = false; return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
            loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
        } catch {
            loginError = "Couldn't change the login item. Run the installed app, not a development build."
            revertingLogin = true
            launchAtLogin = !on
        }
    }
}
