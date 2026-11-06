import AppKit
import SwaplaneCore
import SwiftUI
import Usage

// MARK: Panel root

struct PanelView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !model.loaded {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(28)
            } else if model.accounts.isEmpty {
                EmptyAccountsView(model: model)
            } else {
                LanesView(model: model)
                if let a = model.selected { DetailCard(model: model, account: a).id(a.id) }
            }
            statusStrip
            footer
        }
        .padding(14)
        .frame(width: 380)
        .foregroundStyle(Theme.fg)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .animation(model.motion ? .snappy(duration: 0.25) : nil, value: model.accounts.count)
        .animation(model.motion ? .snappy(duration: 0.25) : nil, value: model.toast)
        .task { await model.reload(); await model.refreshUsage() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("AI Swaplane").font(.system(size: 15, weight: .semibold))
                Text(statusLine).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
            }
            Spacer()
            IconButton(symbol: "gearshape", label: "Settings") { model.onClosePanel?(); model.onOpenSettings?() }
        }
        .padding(.horizontal, 2).padding(.bottom, 10)
    }

    private var statusLine: String {
        if !model.loaded { return "Loading…" }
        if model.accounts.isEmpty { return "No accounts yet" }
        let parts = Tool.allCases.compactMap { t -> String? in
            guard model.probes[t]?.status.allowsSwitching == true else { return nil }
            return "\(t.shortName): \(model.activeAccount(for: t)?.group.label ?? "—")"
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var statusStrip: some View {
        if let phase = model.phaseText {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(phase).font(.system(size: 12)) }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 11)).padding(.top, 9)
        }
        if let err = model.errorMessage {
            Label(err, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(Theme.danger)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 11)).padding(.top, 9)
        }
        if let t = model.toast {
            HStack(spacing: 10) {
                Text(t.message).font(.system(size: 12)).foregroundStyle(t.isError ? Theme.warn : Theme.fg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(t.actions.enumerated()), id: \.offset) { _, a in
                    Button(a.title) { Task { await model.perform(a) } }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.signal)
                }
            }
            .padding(10).background(Theme.card, in: RoundedRectangle(cornerRadius: 11)).padding(.top, 9)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.line).padding(.top, 11)
            HStack {
                AddAccountMenu(model: model)
                Spacer()
                Button("Quit") { model.onQuit?() }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 6).padding(.vertical, 4)
            }.padding(.top, 10)
        }
    }
}

extension ToastAction {
    var title: String {
        switch self {
                case .retry(let t, _): "Retry \(t.shortName)"
        }
    }
}

extension Tool {
    var shortName: String { self == .claudeCode ? "CLI" : "Desktop" }
}

struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14)).frame(width: 28, height: 28)
                .background(hover ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(Theme.muted)
        .onHover { hover = $0 }
        .help(label).accessibilityLabel(label)
    }
}

// MARK: Add account menu

struct AddAccountMenu: View {
    @Bindable var model: AppModel
    var body: some View {
        if model.snapshotMode { menu } else { realMenu }
    }

    private var menu: some View {
        Label("Add account", systemImage: "plus").font(.system(size: 12.5))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }

    private var realMenu: some View {
        Menu {
            ForEach(Tool.allCases, id: \.self) { t in
                if model.probes[t]?.status.allowsSwitching == true, model.detected[t] != nil {
                    Button(importTitle(t)) { model.onClosePanel?(); model.openWizard(tool: t, group: autoGroup(t)) }
                }
            }
            Button("Sign in with another account…") { model.onClosePanel?(); model.openWizard(tool: .claudeCode) }
        } label: {
            Label("Add account", systemImage: "plus").font(.system(size: 12.5))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .padding(.horizontal, 10).padding(.vertical, 5)
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }

    private func autoGroup(_ t: Tool) -> UUID? {
        guard let key = model.detected[t]?.identityKey else { return nil }
        return model.profiles.first { $0.tool != t && $0.identityKey == key && $0.groupID != nil }.flatMap { p in
            model.accounts.first { $0.id == p.groupID && $0.profiles[t] == nil }?.id
        }
    }
    private func importTitle(_ t: Tool) -> String {
        if let g = autoGroup(t), let a = model.accounts.first(where: { $0.id == g }) { return "Add \(t.displayName) to \(a.group.label)" }
        return "Import current \(t.displayName) account"
    }
}

// MARK: Empty / welcome

struct EmptyAccountsView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 22)).foregroundStyle(Theme.signal)
                .frame(width: 46, height: 46).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            Text(found ? "Welcome to AI Swaplane" : "No accounts yet").font(.system(size: 14, weight: .semibold))
            Text(found ? "Switch between AI accounts in one move. Sign-ins stay in your Keychain."
                       : "Sign in to Claude, then import the account here.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            VStack(spacing: 6) {
                ForEach(Tool.allCases, id: \.self) { t in
                    if model.probes[t]?.status.allowsSwitching == true {
                        HStack(spacing: 8) {
                            Image(systemName: model.detected[t] != nil ? "checkmark.circle" : "circle.dashed")
                                .foregroundStyle(model.detected[t] != nil ? Theme.success : Theme.muted)
                            Text(t.displayName)
                            Spacer()
                            Text(model.detected[t] != nil ? "Signed in" + (model.display(model.detected[t]?.displayHint).map { " · \($0)" } ?? "") : "Not signed in")
                                .font(.system(size: 11)).foregroundStyle(Theme.muted)
                        }
                        .font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }.padding(.top, 6)
            if found {
                Button { Task { await model.importDetected() } } label: {
                    Text("Import detected account").font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(Theme.signal, in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(Theme.ink)
                }.buttonStyle(.plain).disabled(model.busy).padding(.top, 4)
            }
        }
        .padding(.vertical, 10)
    }
    private var found: Bool { Tool.allCases.contains { model.unsaved($0) != nil } }
}

// MARK: Lanes with connectors

private struct Link: Shape {
    var y0: CGFloat, y1: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: y0))
        p.addCurve(to: CGPoint(x: 44, y: y1), control1: CGPoint(x: 22, y: y0), control2: CGPoint(x: 22, y: y1))
        return p
    }
}

struct LanesView: View {
    @Bindable var model: AppModel
    @State private var flash: CGFloat = 1
    private let rowH: CGFloat = 46

    var body: some View {
        let accts = model.accounts
        let tools = Tool.allCases.reversed() as [Tool]  // Desktop is the first rank
        let H = max(CGFloat(accts.count) * rowH, CGFloat(tools.count) * 44 + 4)
        let content = ZStack(alignment: .topLeading) {
            connectors(accts, tools, H)
            VStack(spacing: 0) { ForEach(accts) { LaneRow(model: model, account: $0, flash: flash).frame(height: rowH) } }
                .frame(maxHeight: .infinity, alignment: .top)
        }.frame(height: H)
        Group {
            if H > 236 { ScrollView(showsIndicators: false) { content }.frame(height: 236) } else { content }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: model.flashTick) {
            flash = 0
            DispatchQueue.main.async { withAnimation(model.motion ? .easeOut(duration: 0.8) : nil) { flash = 1 } }
        }
    }

    private func connectors(_ accts: [Account], _ tools: [Tool], _ H: CGFloat) -> some View {
        let m = CGFloat(tools.count)
        func ty(_ i: Int) -> CGFloat { H / 2 + (CGFloat(i) - (m - 1) / 2) * 44 }
        return ZStack(alignment: .topLeading) {
            ForEach(Array(accts.enumerated()), id: \.element.id) { i, a in
                let y = CGFloat(i) * rowH + rowH / 2
                ForEach(Array(tools.enumerated()), id: \.offset) { ti, t in
                    if a.profiles[t] != nil {
                        let active = model.isActive(a, on: t)
                        let preview = a.id == model.selected?.id && !active
                        Link(y0: y, y1: ty(ti))
                            .trim(from: 0, to: active && a.id == model.flashID ? flash : 1)
                            .stroke(active ? Theme.signal : preview ? Theme.signal.opacity(0.7) : Theme.line,
                                    style: StrokeStyle(lineWidth: active ? 2.6 : preview ? 2 : 1, lineCap: .round,
                                                       dash: preview ? [4, 3] : []))
                    }
                }
            }
            ForEach(Array(tools.enumerated()), id: \.offset) { ti, t in
                Text(t.shortName).font(.system(size: 11))
                    .frame(width: 76, height: 26)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.signal, lineWidth: 1))
                    .position(x: 38 + 38, y: ty(ti))
                    .opacity(model.probes[t]?.status.allowsSwitching == true ? 1 : 0.35)
            }
        }
        .frame(width: 114, height: H, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 10)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct LaneRow: View {
    @Bindable var model: AppModel
    let account: Account
    let flash: CGFloat
    @State private var hover = false
    @State private var pulse = false
    @State private var draft = ""
    @FocusState private var renameFocus: Bool

    var body: some View {
        let selected = model.selected?.id == account.id
        let active = !model.activeTools(account).isEmpty
        let color = Palette.color(account.group.colorName)
        HStack(spacing: 10) {
            ZStack {
                Circle().strokeBorder(color, lineWidth: 2).background(Circle().fill(active ? color : .clear))
                if pulse { Circle().stroke(Theme.signal, lineWidth: 2).scaleEffect(2.2).opacity(0) }
            }
            .frame(width: 11, height: 11)
            VStack(alignment: .leading, spacing: 1) {
                if model.renamingID == account.id {
                    TextField("Name", text: $draft)
                        .textFieldStyle(.plain).font(.system(size: 13, weight: .medium)).focused($renameFocus)
                        .padding(.horizontal, 5).background(Theme.panel, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.signal))
                        .onSubmit { commit() }
                        .onExitCommand { model.renamingID = nil }
                        .onAppear { draft = account.group.label; renameFocus = true }
                } else {
                    Text(account.group.label).font(.system(size: 13, weight: .medium)).lineLimit(1)
                }
                Text(summary.text).font(.system(size: 11)).foregroundStyle(summary.warn ? Theme.warn : Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            rowMenu
        }
        .padding(.leading, 12).padding(.trailing, 128)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(selected ? Theme.signal.opacity(0.14) : hover ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { model.select(account.id) }
        .onHover { hover = $0 }
        .overlay { if model.removingID == account.id { removeBar } }
        .animation(model.motion ? .easeOut(duration: 0.18) : nil, value: selected)
        .onChange(of: model.flashTick) {
            guard model.flashID == account.id, model.motion else { return }
            pulse = false
            withAnimation(.easeOut(duration: 0.9)) { pulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { pulse = false }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(account.group.label), \(summary.text)\(active ? ", active" : "")")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func commit() {
        let t = draft.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { model.renamingID = nil; return }
        Task { await model.rename(account, to: t) }
    }

    @ViewBuilder private var rowMenu: some View {
        if model.snapshotMode {
            Image(systemName: "ellipsis").font(.system(size: 13)).frame(width: 26, height: 26).foregroundStyle(Theme.muted)
        } else { realRowMenu }
    }

    private var realRowMenu: some View {
        Menu {
            Button("Re-authenticate…") {
                if let p = account.profiles[.claudeCode] ?? account.profiles.values.first {
                    model.onClosePanel?(); model.openWizard(tool: p.tool, group: account.id, reauth: p)
                }
            }
            Button("Re-import current state") { Task { await model.recapture(account) } }
                .disabled(model.activeTools(account).isEmpty)
            Button("Rename") { model.renamingID = account.id }
            Menu("Colour") {
                ForEach(Palette.names, id: \.self) { n in Button(n.capitalized) { Task { await model.recolor(account, to: n) } } }
            }
            Divider()
            Button("Remove…", role: .destructive) { SoundPlayer.shared.play(.warn); model.removingID = account.id }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 13)).frame(width: 26, height: 26).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .foregroundStyle(Theme.muted)
        .accessibilityLabel("More actions for \(account.group.label)")
    }

    private var removeBar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Remove \(account.group.label)?").font(.system(size: 12, weight: .semibold))
                Text("Deletes its saved sign-in.").font(.system(size: 10.5)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button("Cancel") { model.removingID = nil }.buttonStyle(.plain).padding(.horizontal, 10).padding(.vertical, 5)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 8)).font(.system(size: 12))
            Button("Remove") { Task { await model.remove(account) } }.buttonStyle(.plain).padding(.horizontal, 10).padding(.vertical, 5)
                .background(Theme.danger, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(.white).font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.danger))
        .transition(.opacity)
    }

    private var summary: (text: String, warn: Bool) { UsageText.summary(model.usage[account.id]) }
}

enum UsageText {
    static func summary(_ s: UsageSnapshot?) -> (text: String, warn: Bool) {
        guard let s else { return ("Usage not loaded yet", false) }
        switch s.state {
        case .none: return ("No limit", false)
        case .unavailable where s.windows.isEmpty: return ("Usage unavailable", false)
        case .expired where s.windows.isEmpty: return ("Sign-in expired", true)
        default:
            let w = s.windows.map { "\($0.name) \(Int($0.percent.rounded()))%" }.joined(separator: " · ")
            return (w, false)
        }
    }
}

// MARK: Detail card

struct DetailCard: View {
    @Bindable var model: AppModel
    let account: Account

    var body: some View {
        let snap = model.usage[account.id]
        let color = Palette.color(account.group.colorName)
        let active = model.activeTools(account)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 11, height: 11)
                Text(account.group.label).font(.system(size: 14, weight: .semibold))
                Spacer()
                ForEach(active, id: \.self) { t in
                    Text(t.shortName).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.signal)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Theme.signal.opacity(0.16), in: Capsule())
                }
            }
            if let email = model.display(account.identityHint) {
                Text(email).font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.leading, 19).padding(.top, 3)
            }

            usageBody(snap)

            SwitchControls(model: model, account: account).padding(.top, 16)
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .padding(.top, 9)
    }

    @ViewBuilder private func usageBody(_ snap: UsageSnapshot?) -> some View {
        let color = Palette.color(account.group.colorName)
        if let snap, !snap.windows.isEmpty {
            freshness(snap)
            ForEach(Array(snap.windows.enumerated()), id: \.element.name) { i, w in
                VStack(spacing: 3) {
                    HStack {
                        Text(w.name).font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("\(Int(w.percent.rounded()))% used" + (w.resetsAt.map { " · resets " + Self.resetTime($0) } ?? ""))
                            .font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    LimitBar(percent: w.percent, base: color, motion: model.motion)
                }.padding(.top, i == 0 ? 8 : 14)
            }
            if snap.windows.count < 2 { note("No weekly limit shown for this account.") }
            if snap.state == .expired {
                note("Claude Code's sign-in has expired. Run `claude` once, then check again.", icon: "arrow.triangle.2.circlepath", warn: true)
                HStack(spacing: 8) {
                    Chip(title: model.checkingUsage ? "Checking…" : "Check again", on: false) { Task { await model.checkUsageNow() } }
                        .disabled(model.checkingUsage)
                    Chip(title: "Open Terminal", on: false) { model.openTerminal() }
                }.padding(.top, 8)
            }
            ReminderGroup(model: model, account: account, windows: snap.windows).padding(.top, 12)
        } else {
            switch snap?.state {
            case .none?: note("No usage limits on this account. Nothing to track.", icon: "infinity")
            case .expired?:
                note("Claude Code's sign-in has expired. Run `claude` once, then check again.", icon: "arrow.triangle.2.circlepath", warn: true)
                HStack(spacing: 8) {
                    Chip(title: model.checkingUsage ? "Checking…" : "Check again", on: false) { Task { await model.checkUsageNow() } }
                        .disabled(model.checkingUsage)
                    Chip(title: "Open Terminal", on: false) { model.openTerminal() }
                }.padding(.top, 8)
            case .unavailable?: note("Usage unavailable right now. Switching still works.", icon: "icloud.slash")
            default: note("Usage appears after this account has been active.", icon: "chart.bar")
            }
        }
    }

    /// "Updated just now" / "Updated 12 min ago · last known", with a refresh button for the live account.
    private func freshness(_ snap: UsageSnapshot) -> some View {
        let mins = Int(Date().timeIntervalSince(snap.fetchedAt) / 60)
        let age = mins < 1 ? "just now" : mins < 60 ? "\(mins) min ago" : "\(mins / 60) hr ago"
        let text = "Updated \(age)" + (snap.state == .fresh ? "" : " · last known")
        return HStack(spacing: 4) {
            Text(text).font(.system(size: 11)).foregroundStyle(Theme.muted)
            if model.isActive(account, on: .claudeCode) { RefreshButton(busy: model.checkingUsage) { Task { await model.checkUsageNow() } } }
            Spacer(minLength: 0)
        }
        .padding(.leading, 19).padding(.top, 6)
    }

    /// Clock time of the reset: "4:30 PM" today, "Tomorrow 4:30 PM", otherwise "Mon 4:30 PM".
    static func resetTime(_ d: Date) -> String {
        let time = d.formatted(date: .omitted, time: .shortened)
        let cal = Calendar.current
        if cal.isDateInToday(d) { return time }
        if cal.isDateInTomorrow(d) { return "tomorrow " + time }
        return d.formatted(.dateTime.weekday(.abbreviated)) + " " + time
    }

    private func note(_ s: String, icon: String? = nil, warn: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 5) {
            if let icon { Image(systemName: icon) }
            Text(s)
        }.font(.system(size: 11.5)).foregroundStyle(warn ? Theme.warn : Theme.muted).padding(.top, 8)
    }
}

/// Bell that shakes whenever `trigger` changes.
struct ShakeBell: View {
    let symbol: String
    let on: Bool
    let size: CGFloat
    let trigger: Int
    var body: some View {
        Image(systemName: symbol).font(.system(size: size))
            .foregroundStyle(on ? Theme.signal : Theme.muted)
            .keyframeAnimator(initialValue: 0.0, trigger: trigger) { icon, angle in
                icon.rotationEffect(.degrees(angle), anchor: .top)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(18, duration: 0.07)
                    CubicKeyframe(-16, duration: 0.11)
                    CubicKeyframe(12, duration: 0.10)
                    CubicKeyframe(-8, duration: 0.09)
                    CubicKeyframe(4, duration: 0.08)
                    CubicKeyframe(0, duration: 0.07)
                }
            }
    }
}

/// Orange switch with a white knob in both appearances.
struct ToggleSwitch: View {
    let on: Bool
    let motion: Bool
    var body: some View {
        Capsule().fill(on ? Theme.signal : Theme.track).frame(width: 33, height: 20)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle().fill(.white).frame(width: 16, height: 16).shadow(color: .black.opacity(0.3), radius: 1, y: 1).padding(2)
            }
            .animation(motion ? .easeOut(duration: 0.15) : nil, value: on)
    }
}

/// Compact group: one header and a Session / Weekly switch row for each usage window.
struct ReminderGroup: View {
    @Bindable var model: AppModel
    let account: Account
    let windows: [UsageWindow]
    @State private var headerShakes = 0

    var body: some View {
        let any = windows.contains { model.windowReminder(account, $0.name) }
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ShakeBell(symbol: any ? "bell.fill" : "bell", on: any, size: 11, trigger: headerShakes)
                Text("Notify me when limits reset").font(.system(size: 11)).foregroundStyle(any ? Theme.signal : Theme.muted)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.top, 7).padding(.bottom, 5)
            ForEach(windows, id: \.name) { w in
                Divider().overlay(Theme.line)
                ReminderToggleRow(name: w.name, resetsAt: w.resetsAt, on: model.windowReminder(account, w.name), motion: model.motion) {
                    let was = model.windowReminder(account, w.name)
                    model.toggleWindowReminder(account, w.name)
                    if !was && model.motion { headerShakes += 1 }
                }
            }
        }
        .background(Theme.hover, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ReminderToggleRow: View {
    let name: String
    let resetsAt: Date?
    let on: Bool
    let motion: Bool
    let action: () -> Void
    @State private var shakes = 0

    var body: some View {
        Button {
            if !on && motion { shakes += 1 }
            action()
        } label: {
            HStack(spacing: 8) {
                ShakeBell(symbol: on ? "bell.badge.fill" : "bell", on: on, size: 14, trigger: shakes).frame(width: 20)
                Text(name).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.fg)
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(Theme.muted).lineLimit(1)
                Spacer(minLength: 0)
                ToggleSwitch(on: on, motion: motion)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) reset reminder")
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }

    private var subtitle: String {
        on ? (resetsAt.map { "On · notify at " + DetailCard.resetTime($0) } ?? "On") : "Off"
    }
}

/// Small refresh icon button; spins while refreshing.
struct RefreshButton: View {
    let busy: Bool
    let action: () -> Void
    @State private var hover = false
    @State private var angle = 0.0
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
                .rotationEffect(.degrees(angle))
                .frame(width: 18, height: 18)
                .background(hover && !busy ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(busy ? Theme.signal : hover ? Theme.fg : Theme.muted)
        .disabled(busy).onHover { hover = $0 }
        .help("Refresh usage").accessibilityLabel("Refresh usage")
        .onChange(of: busy) {
            if busy { withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { angle = 360 } }
            else { withAnimation(.none) { angle = 0 } }
        }
    }
}

struct Chip: View {
    let title: String
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 11)).padding(.horizontal, 14).padding(.vertical, 5)
                .background(on ? Theme.signal.opacity(0.16) : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? Theme.signal : Theme.line))
        }.buttonStyle(.plain).foregroundStyle(on ? Theme.fg : Theme.muted)
    }
}

struct LimitBar: View {
    let percent: Double
    let base: Color
    let motion: Bool
    @State private var shown = false
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(Theme.limitColor(percent, base: base))
                    .frame(width: g.size.width * (shown ? CGFloat(min(100, max(0, percent)) / 100) : 0))
            }
        }
        .frame(height: 5)
        .onAppear { withAnimation(motion ? .easeOut(duration: 0.7) : nil) { shown = true } }
        .accessibilityElement().accessibilityLabel("\(Int(percent.rounded())) percent used")
    }
}

// MARK: Switch controls (tool selector + hold to switch)

struct SwitchControls: View {
    @Bindable var model: AppModel
    let account: Account

    var body: some View {
        let cands = model.candidateTools(for: account)
        let tools = model.switchTools(for: account)
        VStack(spacing: 0) {
            if model.accounts.count == 1 {
                Text("This is your only account. Add another to start switching.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
            } else if cands.isEmpty {
                Label("Already active", systemImage: "checkmark")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).frame(height: 34)
                    .background(Theme.hover, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
            } else {
                if cands.count > 1 { selector(cands) }
                HoldToSwitchButton(
                    title: "Hold to switch \(tools.map(\.shortName).joined(separator: " + ")) to \(account.group.label)",
                    motion: model.motion, enabled: !model.busy
                ) { Task { await model.switchSelected() } }
                .padding(.top, cands.count > 1 ? 8 : 0)
                Text("Press and hold to confirm. Release to cancel.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.top, 6)
                ForEach(model.missingTools(account), id: \.self) { t in
                    Button("Add \(t.displayName) to this account…") { model.onClosePanel?(); model.openWizard(tool: t, group: account.id) }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.signal).padding(.top, 6)
                }
            }
        }
    }

    private func selector(_ cands: [Tool]) -> some View {
        HStack(spacing: 4) {
            seg("Both", on: model.target == .all) { model.target = .all }
            ForEach(cands, id: \.self) { t in seg("\(t.shortName) only", on: model.target == .only(t)) { model.target = .only(t) } }
        }
        .padding(3).background(Theme.panel, in: RoundedRectangle(cornerRadius: 9))
    }

    private func seg(_ s: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button { SoundPlayer.shared.play(.tick); action() } label: {
            Text(s).font(.system(size: 11.5, weight: on ? .medium : .regular)).frame(maxWidth: .infinity).padding(.vertical, 4)
                .background(on ? Theme.signal : .clear, in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(on ? Theme.ink : Theme.muted)
        }.buttonStyle(.plain)
    }
}

struct HoldToSwitchButton: View {
    let title: String
    let motion: Bool
    let enabled: Bool
    let onFire: () -> Void
    private let duration = 0.9
    @State private var progress: CGFloat = 0
    @State private var holding = false
    @State private var fired = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10).fill(Theme.signal)
            GeometryReader { g in Rectangle().fill(.black.opacity(0.26)).frame(width: g.size.width * progress) }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink).frame(maxWidth: .infinity)
        }
                .frame(height: 34)
        .scaleEffect(holding && motion ? 0.985 : 1)
        .opacity(enabled ? 1 : 0.5)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in start() }.onEnded { _ in cancel(); fired = false })
        .focusable()
        .onKeyPress(keys: [.space, .return], phases: [.down, .up]) { p in
            if p.phase == .down { start() } else { cancel(); fired = false }
            return .handled
        }
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityHint("Press and hold, or use the Activate action, to switch.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if enabled { onFire() } }
    }

    private func start() {
        guard enabled, !holding, !fired else { return }
        holding = true
        SoundPlayer.shared.play(.tick)
        withAnimation(.linear(duration: motion ? duration : 0.01)) { progress = 1 }
        task = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, holding else { return }
            holding = false; fired = true; progress = 0
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            onFire()
        }
    }
    private func cancel() {
        guard holding else { return }
        holding = false
        task?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { progress = 0 }
    }
}
