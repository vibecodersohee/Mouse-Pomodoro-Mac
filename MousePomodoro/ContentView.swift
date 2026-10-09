import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var engine: TimerEngine

    @State private var planDailyTotal = 1
    @State private var planFocusMinutes = 25
    @State private var planBreakMinutes = 5
    @State private var nameDraft = ""

    var body: some View {
        ZStack {
            if engine.compact {
                CompactStripView(engine: engine)
            } else {
                VStack(spacing: 0) {
                    HeaderBar(
                        mouseName: engine.mouseName,
                        cheeseLabel: engine.cheeseLabel,
                        onCalendar: {
                            engine.overlay == .weeklyStats ? engine.closeWeeklyStats() : engine.openWeeklyStats()
                        },
                        onCollapse: { engine.toggleCompact() },
                        collapseDisabled: engine.view == .plan,
                        onSettings: {
                            engine.overlay == .settings ? engine.closeSettings() : engine.openSettings()
                        },
                        onQuit: { engine.openConfirmQuit() }
                    )

                    if engine.overlay == .weeklyStats {
                        WeeklyStatsView(engine: engine)
                    } else {
                        screen
                        bottom
                    }
                }
                .frame(width: 340)
                .background(SwiftUI.Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.Color.border, lineWidth: 1))

                if engine.overlay != .none, engine.overlay != .weeklyStats {
                    overlayContent
                }
            }
        }
        .frame(width: engine.compact ? 232 : 340, height: contentHeight)
        .onChange(of: engine.view) { _, newValue in
            if newValue == .plan {
                planDailyTotal = engine.dailyTotal
                planFocusMinutes = engine.focusMinutes
                planBreakMinutes = engine.breakMinutes
            }
        }
        .onChange(of: engine.overlay) { _, newValue in
            if newValue == .naming {
                nameDraft = ""
            }
        }
        .onChange(of: engine.noteText) { _, newValue in
            guard newValue != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                engine.dismissNote()
            }
        }
    }

    /// Same heights the AppDelegate gives the popover, so SwiftUI's measured size never
    /// disagrees with the NSPopover's `contentSize`.
    private var contentHeight: CGFloat {
        engine.compact ? 84 : engine.popoverHeight
    }

    private func planStart() {
        engine.startPlan(dailyTotal: planDailyTotal, focusMinutes: planFocusMinutes, breakMinutes: planBreakMinutes)
    }

    // MARK: - Screen (middle card)

    @ViewBuilder
    private var screen: some View {
        switch engine.view {
        case .idle:
            ScreenCard {
                idleTitle
                AnimatedSpriteView(sprite: .idle, motion: .bob, size: 128)
            }
        case .plan:
            ScreenCard(background: DS.Color.screenCard) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today's sessions")
                        .font(DS.Font.bold(16))
                    Text("Customize your daily total sessions, focus and break durations.")
                        .font(DS.Font.regular(12))
                        .opacity(0.7)
                }
                .foregroundStyle(DS.Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

                inputRow(label: "Daily total", value: $planDailyTotal, bounds: 1...20, unit: "sessions")
                VStack(spacing: 8) {
                    inputRow(label: "Focus", value: $planFocusMinutes, bounds: 1...90, unit: "minutes")
                    inputRow(label: "Break", value: $planBreakMinutes, bounds: 1...30, unit: "minutes")
                }
            }
        case .focus:
            ScreenCard(sceneImageName: engine.activeScene(.focus), spacing: 12) {
                ZStack(alignment: .bottom) {
                    VStack(spacing: 12) {
                        TimerPill(label: engine.showsPaused ? "FOCUS Time: Paused" : "FOCUS Time", progress: engine.planProgressLabel, time: formatted(engine.remaining), dimmed: engine.showsPaused)
                        // Paused Focus = the sleeping pose, no motion (plugin's spriteState()).
                        AnimatedSpriteView(
                            sprite: engine.showsPaused ? .sleeping : .focusing,
                            motion: engine.showsPaused ? .none : .bob,
                            size: 128
                        )
                    }
                    .frame(maxHeight: .infinity, alignment: .top)

                    // Speech bubble sits below the character, at the bottom of the card.
                    if let note = engine.noteText {
                        NoteBubble(text: note) { engine.dismissNote() }
                            .transition(.opacity)
                    }
                }
            }
        case .complete:
            ScreenCard {
                VStack(spacing: 4) {
                    Text(engine.milestoneHit != nil ? "\(engine.milestoneHit!) sessions!" : "Session complete!")
                        .font(DS.Font.bold(16))
                        .foregroundStyle(DS.Color.inkSoft)
                    if let n = engine.milestoneHit {
                        Text(SceneCatalog.milestoneCopy(for: n) + (SceneCatalog.isLevelUpMilestone(n) ? " New background unlocked!" : ""))
                            .font(DS.Font.regular(11))
                            .foregroundStyle(DS.Color.inkSoft.opacity(0.8))
                            .multilineTextAlignment(.center)
                    } else if let streak = engine.lastStreakLabel {
                        Text(streak)
                            .font(DS.Font.semibold(12))
                            .foregroundStyle(DS.Color.inkSoft)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 2)
                            .background(DS.Color.screenCard)
                            .clipShape(Capsule())
                    } else {
                        Image("icon-cheese")
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 24, height: 24)
                            .foregroundStyle(DS.Color.inkSoft)
                    }
                    Text(engine.lastCreditLabel)
                        .font(DS.Font.bold(32))
                        .foregroundStyle(DS.Color.ink)
                }
                if let n = engine.milestoneHit {
                    AnimatedGIFView(resourceName: SceneCatalog.milestoneArt(for: n), size: 128)
                        .frame(width: 128, height: 128)
                } else {
                    AnimatedSpriteView(sprite: .cheese, motion: .pop, size: 128)
                }
            }
        case .breakTime:
            ScreenCard(sceneImageName: engine.activeScene(.breakTime), spacing: 12) {
                TimerPill(label: engine.showsPaused ? "Break Time: Paused" : "Break Time", progress: engine.planProgressLabel, time: formatted(engine.remaining), dimmed: engine.showsPaused)
                AnimatedSpriteView(sprite: engine.breakPose, motion: breakMotion(for: engine), size: 128, restartToken: engine.jumpCount)
                    .contentShape(Rectangle())
                    .onTapGesture { engine.jump() }
                Text("Tap to jump · Move cursor to dance")
                    .font(DS.Font.regular(11))
                    .foregroundStyle(DS.Color.inkSoft.opacity(0.75))
            }
            // Like the plugin, the whole card (not just the sprite) reacts to the cursor.
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active: engine.breakCursorMoved()
                case .ended: engine.breakCursorLeft()
                }
            }
        case .entireComplete:
            ScreenCard {
                VStack(spacing: 4) {
                    Text(todayDateLabel)
                        .font(DS.Font.bold(16))
                        .foregroundStyle(DS.Color.inkSoft)
                    Text(engine.todaySessionsLabel)
                        .font(DS.Font.bold(16))
                        .foregroundStyle(DS.Color.inkSoft)
                    Text(engine.todayDurationLabel)
                        .font(DS.Font.bold(32))
                        .foregroundStyle(DS.Color.ink)
                }
                AnimatedSpriteView(sprite: .idle, motion: .bob, size: 128)
            }
        }
    }

    private var todayDateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd/yyyy"
        return f.string(from: Date())
    }

    private var idleTitle: some View {
        VStack(spacing: 0) {
            Text("Move your")
                .font(DS.Font.bold(16))
                .foregroundStyle(DS.Color.inkSoft)
            HStack(spacing: 4) {
                Image("icon-mouse")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 24, height: 24)
                Text("Mouse")
                    .font(DS.Font.bold(32))
                Image("icon-mouse")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 24, height: 24)
            }
            .foregroundStyle(DS.Color.ink)
        }
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottom: some View {
        switch engine.view {
        case .idle:
            BottomBar {
                PrimaryButton(title: "Plan your sessions", icon: "icon-map") {
                    engine.tapPlanButton()
                }
            }
        case .plan:
            BottomBar {
                PrimaryButton(title: "Start Focus Session", icon: "icon-play") {
                    planStart()
                }
            }
        case .focus:
            BottomBar {
                PrimaryButton(title: engine.showsPaused ? "Resume" : "Pause", icon: engine.showsPaused ? "icon-play" : "icon-pause") {
                    engine.togglePause()
                }
                SecondaryButtonRow(items: [
                    ("End session early", { engine.openConfirmEnd() }),
                    ("Wrap up today", { engine.openConfirmWrap() }),
                ])
            }
        case .complete:
            // Figma's Complete footer has no button at all — it auto-advances
            // to Break after a countdown. Tapping the text skips the wait.
            BottomBar {
                Text("Starting your break automatically in \(engine.completeCountdown ?? 0)s…")
                    .font(DS.Font.regular(11))
                    .foregroundStyle(DS.Color.inkSoft.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .onTapGesture { engine.startBreak() }
            }
        case .breakTime:
            BottomBar {
                PrimaryButton(title: "Feed for a snack", icon: "icon-cheese") {
                    engine.feed()
                }
                .opacity(engine.showsPaused ? 0.5 : 1)
                .disabled(engine.showsPaused)
                SecondaryButtonRow(items: [
                    (engine.showsPaused ? "Resume" : "Pause", { engine.togglePause() }),
                    ("Skip break", { engine.skipBreak() }),
                    ("Wrap up today", { engine.openConfirmWrap() }),
                ], spaced: true)
            }
        case .entireComplete:
            BottomBar {
                SecondaryButtonRow(items: [
                    ("Download Image", { exportSticker() }),
                    (engine.planWrappedEarly ? "Resume sessions" : "Add more sessions", { engine.continueFromEntireComplete() }),
                ])
            }
        }
    }

    @MainActor
    private func exportSticker() {
        let sticker = StickerView(
            dateLabel: todayDateLabel,
            sessionsLabel: engine.todaySessionsLabel,
            durationLabel: engine.todayDurationLabel
        )
        let renderer = ImageRenderer(content: sticker)
        renderer.scale = 2
        guard let nsImage = renderer.nsImage else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "mouse-pomodoro-\(ISO8601DateFormatter().string(from: Date()).prefix(10)).png"
        panel.allowedContentTypes = [.png]
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let tiff = nsImage.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let data = rep.representation(using: .png, properties: [:]) else { return }
            try? data.write(to: url)
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var overlayContent: some View {
        switch engine.overlay {
        case .none:
            EmptyView()
        case .naming:
            ConfirmScrim {
                NamingCard(name: $nameDraft) {
                    engine.confirmName(nameDraft)
                }
            }
        case .settings:
            ConfirmScrim {
                SettingsCard(engine: engine)
            }
        case .confirmEnd:
            ConfirmScrim {
                ConfirmCard(
                    title: "End this session?",
                    subtitle: "No penalty either way! You'll still get a little credit for the effort.",
                    confirmTitle: "End session",
                    confirmIsDestructive: true,
                    onKeepGoing: { engine.dismissConfirm() },
                    onConfirm: { engine.confirmEndSession() }
                )
            }
        case .confirmWrap:
            ConfirmScrim {
                ConfirmCard(
                    title: "End today's entire session?",
                    subtitle: "You did amazing work today!",
                    confirmTitle: "Wrap up",
                    confirmIsDestructive: true,
                    onKeepGoing: { engine.dismissConfirm() },
                    onConfirm: { engine.confirmWrapUp() }
                )
            }
        case .confirmQuit:
            ConfirmScrim {
                ConfirmCard(
                    title: "Quit Move Your Mouse?",
                    subtitle: "Your progress is saved. See you soon!",
                    keepGoingTitle: "Back",
                    confirmTitle: "Quit",
                    confirmIsDestructive: true,
                    onKeepGoing: { engine.dismissQuit() },
                    onConfirm: { NSApp.terminate(nil) }
                )
            }
        case .weeklyStats:
            EmptyView() // rendered in place of screen/bottom instead — see `body`
        }
    }

    private func inputRow(label: String, value: Binding<Int>, bounds: ClosedRange<Int>, unit: String) -> some View {
        InputRow(label: label, value: value, bounds: bounds, unit: unit)
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// Break motion per the plugin: jump = hop, dancing = wiggle, feeding/regular = bob
/// (regular stands still while paused).
@MainActor
private func breakMotion(for engine: TimerEngine) -> SpriteMotion {
    switch engine.breakPose {
    case .jumping: return .hop
    case .dancing: return .wiggle
    case .feeding: return .bob
    default: return engine.showsPaused ? .none : .bob
    }
}

/// Dim backdrop + centered ivory card, ported from the Figma confirm/settings overlay pattern.
private struct ConfirmScrim<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(DS.Color.overlayDim)
            content()
                .padding(16)
                .background(DS.Color.bottomBar)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(26)
        }
    }
}

private struct ConfirmCard: View {
    let title: String
    let subtitle: String
    var keepGoingTitle = "Keep going!"
    let confirmTitle: String
    let confirmIsDestructive: Bool
    let onKeepGoing: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(DS.Font.bold(16))
                Text(subtitle)
                    .font(DS.Font.regular(12))
                    .multilineTextAlignment(.leading)
                    .opacity(0.7)
            }
            .foregroundStyle(DS.Color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)

            SecondaryButtonRow(danger: [
                (keepGoingTitle, false, onKeepGoing),
                (confirmTitle, confirmIsDestructive, onConfirm),
            ])
        }
        .frame(width: 264 - 32)
    }
}

private struct SettingsCard: View {
    @ObservedObject var engine: TimerEngine
    @State private var dailyTotal: Int
    @State private var focusMinutes: Int
    @State private var breakMinutes: Int
    @State private var tab: Tab = .settings

    private enum Tab { case settings, shop }

    init(engine: TimerEngine) {
        self.engine = engine
        _dailyTotal = State(initialValue: engine.dailyTotal)
        _focusMinutes = State(initialValue: engine.focusMinutes)
        _breakMinutes = State(initialValue: engine.breakMinutes)
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    tabButton("Settings", tab: .settings)
                    tabButton("Shop", tab: .shop)
                }

                if tab == .settings {
                    settingsContent
                } else {
                    ShopTabView(engine: engine)
                }
            }
            // Fixed so the modal doesn't change height between tabs (Figma: 320 max).
            .frame(height: 234, alignment: .top)

            HStack(spacing: 8) {
                Button { engine.closeSettings() } label: {
                    Text("Close")
                        .font(DS.Font.semibold(14))
                        .foregroundStyle(DS.Color.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                PrimaryButton(title: "Save") {
                    engine.updateSettings(dailyTotal: dailyTotal, focusMinutes: focusMinutes, breakMinutes: breakMinutes)
                    engine.closeSettings()
                }
            }
        }
        .frame(width: 256)
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set your daily sessions, focus length and break length.")
                .font(DS.Font.regular(12))
                .foregroundStyle(DS.Color.ink.opacity(0.7))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            InputRow(label: "Daily total", value: $dailyTotal, bounds: 1...20, unit: "sessions")
            VStack(spacing: 8) {
                InputRow(label: "Focus", value: $focusMinutes, bounds: 1...90, unit: "minutes")
                InputRow(label: "Break", value: $breakMinutes, bounds: 1...30, unit: "minutes")
            }
            HStack {
                Text("Show time in menu bar")
                    .font(DS.Font.regular(14))
                    .foregroundStyle(DS.Color.ink)
                Spacer(minLength: 8)
                PixelToggle(isOn: Binding(
                    get: { engine.showMenuBarTime },
                    set: { engine.setShowMenuBarTime($0) }
                ))
            }
        }
    }

    private func tabButton(_ title: String, tab target: Tab) -> some View {
        Button { tab = target } label: {
            Text(title)
                .font(DS.Font.bold(16))
                .foregroundStyle(DS.Color.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(tab == target ? DS.Color.primaryButton : DS.Color.tabInactive)
                        .frame(height: tab == target ? 2 : 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One Plan/Settings row: label on the left, 48px input + unit on the right
/// (the unit column is a fixed 60px so every input lines up, like Figma's 116px group).
private struct InputRow: View {
    let label: String
    @Binding var value: Int
    let bounds: ClosedRange<Int>
    let unit: String

    var body: some View {
        HStack {
            Text(label)
                .font(DS.Font.regular(14))
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                NumberField(value: $value, range: bounds)
                Text(unit)
                    .font(DS.Font.regular(14))
                    .frame(width: 60, alignment: .leading)
            }
        }
        .foregroundStyle(DS.Color.ink)
    }
}

/// Shop tab inside Settings (Figma 239:7681). Backgrounds only ever apply to
/// Break time; Focus always shows the level's office. Every scene costs 20 cheese,
/// locked scenes are shown (not hidden) with what unlocks them, and buying
/// starts using the scene immediately (spend-only, nothing is ever taken away).
private struct ShopTabView: View {
    @ObservedObject var engine: TimerEngine

    private var breakItems: [ShopItem] {
        SceneCatalog.shopItems.filter { $0.holiday == nil }
    }

    private var seasonalItems: [ShopItem] {
        SceneCatalog.shopItems.filter { $0.holiday != nil }
    }

    /// "Basic park" is in use whenever no owned custom scene is picked.
    private var basicInUse: Bool {
        guard let id = engine.sceneBreakOverride else { return true }
        return !engine.owned.contains(id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Text("LV. \(engine.level)")
                HStack(spacing: 4) {
                    Image("icon-cheese")
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text("\(engine.cheeseLabel) cheese")
                }
            }
            .font(DS.Font.semibold(14))
            .foregroundStyle(DS.Color.inkSoft)

            Text("Backgrounds are applied during break time only.")
                .font(DS.Font.regular(12))
                .foregroundStyle(DS.Color.ink.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("Break scene")
                    ShopItemRow(
                        sceneName: SceneCatalog.basicBreakScene(),
                        name: "Basic park",
                        detail: "Basic · Follows the season (now: \(SceneCatalog.season(for: Date()).capitalized))",
                        state: basicInUse ? .inUse : .notInUse,
                        onUse: { engine.setScene(nil, slot: .breakTime) }
                    )
                    ForEach(breakItems) { shopRow($0) }

                    sectionTitle("Seasonal scene")
                        .padding(.top, 8)
                    ForEach(seasonalItems) { shopRow($0) }
                }
                .padding(.trailing, 12)
            }
            .scrollIndicators(.automatic)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(DS.Font.semibold(14))
            .foregroundStyle(DS.Color.ink)
    }

    private func shopRow(_ item: ShopItem) -> some View {
        let state: ShopItemRow.State
        if !engine.isUnlocked(item) {
            state = .locked
        } else if engine.isOwned(item) {
            state = engine.sceneBreakOverride == item.id ? .inUse : .notInUse
        } else {
            state = .forSale(moreToGo: max(0, Int((Double(SceneCatalog.price) - engine.cheeseCount).rounded(.up))))
        }

        let detail: String
        if state == .locked {
            let level = item.unlockLevel
            detail = "Unlocks at level \(level) · \(SceneCatalog.sessionsRequired(forLevel: level)) sessions"
        } else if let holiday = item.holiday {
            detail = "Break scene · Shows \(SceneCatalog.windowLabel(for: holiday))"
        } else {
            detail = "Break scene"
        }

        return ShopItemRow(
            sceneName: item.id,
            name: item.name,
            detail: detail,
            state: state,
            onUse: { engine.setScene(item.id, slot: item.slot) },
            onBuy: { engine.purchase(item) }
        )
    }
}

/// Figma "shop item" component (236:5812): 72×60 thumbnail, name, description and
/// a state-dependent action row — Before purchase / Not in use / In use / Locked.
private struct ShopItemRow: View {
    enum State: Equatable {
        case forSale(moreToGo: Int)
        case notInUse
        case inUse
        case locked
    }

    let sceneName: String
    let name: String
    let detail: String
    let state: State
    var onUse: () -> Void = {}
    var onBuy: () -> Void = {}

    private var background: Color {
        switch state {
        case .inUse: return DS.Color.shopItemActive
        case .locked: return DS.Color.shopItemLocked
        default: return DS.Color.shopItem
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image("scene-\(sceneName)")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 72, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay {
                    if state == .locked {
                        RoundedRectangle(cornerRadius: 4).fill(SwiftUI.Color.black.opacity(0.25))
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(DS.Font.bold(14))
                    .foregroundStyle(SwiftUI.Color(hex: "#1f2717"))
                Text(detail)
                    .font(DS.Font.medium(10))
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                action
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay {
            if state == .inUse {
                RoundedRectangle(cornerRadius: 4).strokeBorder(DS.Color.shopItemActiveBorder, lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var action: some View {
        switch state {
        case .forSale(let moreToGo):
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image("icon-cheese")
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text("\(SceneCatalog.price)")
                        .font(DS.Font.semibold(14))
                }
                .foregroundStyle(DS.Color.ink)
                if moreToGo > 0 {
                    Text("\(moreToGo) more to go")
                        .font(DS.Font.medium(10))
                        .foregroundStyle(SwiftUI.Color(hex: "#576d40"))
                } else {
                    pill("Buy", dimmed: false, action: onBuy)
                }
            }
        case .notInUse:
            pill("Use", dimmed: false, action: onUse)
        case .inUse:
            pill("In use", dimmed: true, action: nil)
        case .locked:
            pill("Locked", dimmed: true, action: nil)
        }
    }

    private func pill(_ title: String, dimmed: Bool, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            Text(title)
                .font(DS.Font.semibold(12))
                .foregroundStyle(DS.Color.secondaryText)
                .padding(4)
                .background(dimmed ? SwiftUI.Color.black.opacity(0.1) : SwiftUI.Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .opacity(dimmed ? 0.6 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

/// The one-time "What's your mouse's name?" prompt, gating Idle's "Plan your
/// sessions" button the first time (mandatory, Confirm disabled until non-blank).
private struct NamingCard: View {
    @Binding var name: String
    let onConfirm: () -> Void

    private var canConfirm: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What's your mouse's name?")
                    .font(DS.Font.bold(16))
                Text("Give your focus companion a name to get started.")
                    .font(DS.Font.regular(12))
                    .opacity(0.7)
            }
            .foregroundStyle(DS.Color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)

            TextField("e.g. Mouse", text: $name)
                .textFieldStyle(.plain)
                .font(DS.Font.regular(14))
                .padding(8)
                .background(DS.Color.inputBackground)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(DS.Color.border, lineWidth: 1))
                .onSubmit { if canConfirm { onConfirm() } }

            PrimaryButton(title: "Confirm") {
                if canConfirm { onConfirm() }
            }
            .opacity(canConfirm ? 1 : 0.5)
            .disabled(!canConfirm)
        }
        .frame(width: 264 - 32)
    }
}

/// The once-per-day encouragement speech bubble shown under the mouse on the
/// Focus screen. Tap to dismiss; also auto-hides after 8s (see ContentView's
/// onChange(of: engine.noteText)).
private struct NoteBubble: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        Text(text)
            .font(DS.Font.regular(12))
            .foregroundStyle(DS.Color.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(SwiftUI.Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DS.Color.ink, lineWidth: 2))
            .onTapGesture(perform: onDismiss)
    }
}

/// Offscreen 512x512 composition for the "Download Image" sticker export —
/// date, session count, today's total time, and the idle-pose sprite.
private struct StickerView: View {
    let dateLabel: String
    let sessionsLabel: String
    let durationLabel: String

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text(dateLabel)
                    .font(DS.Font.bold(32))
                Text(sessionsLabel)
                    .font(DS.Font.bold(32))
                Text(durationLabel)
                    .font(DS.Font.bold(64))
            }
            .foregroundStyle(DS.Color.inkSoft)
            SpriteView(sprite: .idle, size: 256)
        }
        .padding(32)
        .frame(width: 512, height: 512)
        .background(DS.Color.screenCard)
    }
}

/// Weekly stats, built to Figma's "15 - weekly-stats": week navigator, three stat
/// columns, a 13-week × Mon–Sun date grid (oldest → newest, this week outlined),
/// a note + Less/More legend, and a "Back to timer" footer. The header's calendar
/// icon toggles it; it closes by itself when a session completes.
private struct WeeklyStatsView: View {
    @ObservedObject var engine: TimerEngine

    private static let cell: CGFloat = 17
    private static let dayLetters = ["M", "T", "W", "T", "F", "S", "S"]
    private static let levelColors: [Color] = [
        Color.black.opacity(0.1), Color(hex: "#a9c884"), Color(hex: "#7c945b"), Color(hex: "#2f3a23"),
    ]

    private var faint: Color { DS.Color.inkSoft.opacity(0.6) }

    /// Figma shows three greens; the plugin's old five buckets collapse to
    /// 1–2 · 3–4 · 5+ sessions a day.
    private func color(for sessions: Int) -> Color {
        switch sessions {
        case 0: return Self.levelColors[0]
        case 1...2: return Self.levelColors[1]
        case 3...4: return Self.levelColors[2]
        default: return Self.levelColors[3]
        }
    }

    private var summary: WeekSummary { engine.summary(for: engine.selectedWeekStart) }

    private var rangeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let end = Calendar.current.date(byAdding: .day, value: 6, to: engine.selectedWeekStart) ?? engine.selectedWeekStart
        return "\(f.string(from: engine.selectedWeekStart)) - \(f.string(from: end))"
    }

    private var note: String {
        if summary.sessions > 0, let best = summary.bestDayLabel { return best }
        return engine.selectedWeekTitle == "This week" ? "A fresh week - no pressure!" : "A quiet week - that's okay!"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenCard(fixedHeight: nil) {
                levelBanner
                weekHeader
                statsRow
                if let chip = engine.statsStreakChipText {
                    Text(chip)
                        .font(DS.Font.semibold(12))
                        .foregroundStyle(DS.Color.inkSoft)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .background(SwiftUI.Color.white.opacity(0.6))
                        .clipShape(Capsule())
                }
                dateGrid
                footerRow
            }
            BottomBar {
                SecondaryButtonRow(items: [("Back to timer", { engine.closeWeeklyStats() })])
            }
        }
    }

    /// "LV. 2 · Total 23 sessions" (Figma 236:6012).
    private var levelBanner: some View {
        let total = engine.totalSessionsCompleted
        return Text("LV. \(engine.level) · Total \(total) \(total == 1 ? "session" : "sessions")")
            .font(DS.Font.semibold(14))
            .foregroundStyle(SwiftUI.Color(hex: "#fafbf9"))
            .frame(maxWidth: .infinity)
            .padding(4)
            .background(DS.Color.levelBanner)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var weekHeader: some View {
        HStack {
            chevron("icon-chevron-left", enabled: engine.canGoToPreviousWeek) { engine.navigateWeek(by: -1) }
            Spacer()
            VStack(spacing: 4) {
                Text(engine.selectedWeekTitle)
                    .font(DS.Font.bold(16))
                    .foregroundStyle(DS.Color.inkSoft)
                Text(rangeLabel)
                    .font(DS.Font.bold(12))
                    .foregroundStyle(faint)
            }
            Spacer()
            chevron("icon-chevron-right", enabled: engine.canGoToNextWeek) { engine.navigateWeek(by: 1) }
        }
        .frame(maxWidth: .infinity)
    }

    private func chevron(_ name: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(name)
                .renderingMode(.template)
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundStyle(DS.Color.ink)
                .opacity(enabled ? 1 : 0.3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statColumn(value: "\(summary.sessions)", label: "Sessions")
            statColumn(value: TimerEngine.formatDurationShort(summary.minutes), label: "Focused")
            statColumn(value: TimerEngine.formatCheese(summary.cheese), label: "Cheese")
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(DS.Font.bold(24))
                .foregroundStyle(DS.Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(DS.Font.medium(12))
                .foregroundStyle(faint)
        }
        .frame(maxWidth: .infinity)
    }

    private var dateGrid: some View {
        let weeks = engine.heatmapWeeks()
        let cal = Calendar.current
        let today = Date()
        return HStack(alignment: .top, spacing: 4) {
            VStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    Text(Self.dayLetters[i])
                        .font(DS.Font.medium(12))
                        .foregroundStyle(faint)
                        .frame(width: 10, height: Self.cell)
                }
            }
            ForEach(weeks.indices, id: \.self) { col in
                let week = weeks[col]
                let selected = cal.isDate(week[0].date, inSameDayAs: engine.selectedWeekStart)
                VStack(spacing: 4) {
                    ForEach(week) { day in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(for: day.sessions))
                            .frame(width: Self.cell, height: Self.cell)
                            .overlay {
                                if cal.isDate(day.date, inSameDayAs: today) {
                                    RoundedRectangle(cornerRadius: 2).strokeBorder(SwiftUI.Color.black, lineWidth: 2)
                                }
                            }
                    }
                }
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Self.levelColors[3], lineWidth: 1)
                            .padding(-4)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { engine.selectWeek(week[0].date) }
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 2).fill(SwiftUI.Color.white))
    }

    private var footerRow: some View {
        HStack {
            Text(note)
                .font(DS.Font.medium(10))
                .foregroundStyle(faint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Text("Less").font(DS.Font.medium(10)).foregroundStyle(faint)
                ForEach(0..<4, id: \.self) { i in
                    Rectangle().fill(Self.levelColors[i]).frame(width: 12, height: 12)
                }
                Text("More").font(DS.Font.medium(10)).foregroundStyle(faint)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(SwiftUI.Color.white))
        }
        .frame(maxWidth: .infinity)
    }
}

/// The 232x84 minimized strip, built to the Figma "minimized screens" frames
/// (16–20) and the plugin's `miniHTML()`: green card, 64px sprite, bold label over
/// a big time/message, 32px buttons stacked on the right. It floats as its own
/// panel (see AppDelegate) and is as interactive as the full Break screen.
private struct CompactStripView: View {
    @ObservedObject var engine: TimerEngine

    private var running: Bool { engine.view == .focus || engine.view == .breakTime }

    private var sprite: MouseSprite {
        switch engine.view {
        case .focus: return engine.showsPaused ? .sleeping : .focusing
        case .complete: return .cheese
        case .breakTime: return engine.breakPose
        default: return .idle
        }
    }

    private var motion: SpriteMotion {
        switch engine.view {
        case .focus: return engine.showsPaused ? .none : .bob
        case .breakTime: return breakMotion(for: engine)
        case .complete: return .pop
        default: return .bob
        }
    }

    private var label: String {
        switch engine.view {
        case .focus: return engine.showsPaused ? "FOCUS: Paused" : "FOCUS"
        case .breakTime: return engine.showsPaused ? "BREAK: Paused" : "BREAK"
        case .complete: return engine.lastCompleteEarly ? "Nice effort!" : "Session complete!"
        case .entireComplete: return "All done today!"
        default: return engine.mouseName
        }
    }

    private var big: String {
        switch engine.view {
        case .focus, .breakTime:
            let total = max(0, Int(engine.remaining.rounded()))
            return String(format: "%02d:%02d", total / 60, total % 60)
        case .complete: return engine.lastCreditLabel
        case .entireComplete: return engine.todayDurationLabel
        default: return "Ready?"
        }
    }

    private var bigSize: CGFloat {
        switch engine.view {
        case .complete, .entireComplete: return 20
        default: return 24
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            AnimatedSpriteView(sprite: sprite, motion: motion, size: 64, restartToken: engine.jumpCount)
                .contentShape(Rectangle())
                .onTapGesture { engine.jump() }

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(DS.Font.bold(12))
                    .foregroundStyle(DS.Color.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(big)
                    .font(DS.Font.bold(bigSize))
                    .foregroundStyle(DS.Color.ink.opacity(running && engine.showsPaused ? 0.45 : 1))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            VStack(spacing: 4) {
                if running {
                    stripButton(engine.showsPaused ? "icon-play" : "icon-pause", primary: true) { engine.togglePause() }
                } else if engine.view == .idle {
                    stripButton("icon-map", primary: true) { engine.expandAndPlan() }
                }
                stripButton("icon-expand", primary: false) { engine.toggleCompact() }
            }
        }
        .padding(8)
        .frame(width: 232, height: 84)
        .background(DS.Color.screenCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.Color.border, lineWidth: 1))
        // Like the plugin (mousemove on the whole strip): moving the cursor over it
        // makes the mouse dance during Break.
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active: engine.breakCursorMoved()
            case .ended: engine.breakCursorLeft()
            }
        }
    }

    private func stripButton(_ icon: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundStyle(primary ? SwiftUI.Color.white : DS.Color.ink)
                .padding(4)
                .background(primary ? DS.Color.primaryButton : SwiftUI.Color.white.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView(engine: TimerEngine())
}
