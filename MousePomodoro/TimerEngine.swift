import Foundation
import Combine
import UserNotifications

/// `idle -> plan -> focus <-> (paused) -> complete -> break <-> (paused) ->
/// (chain back to focus, or -> entireComplete) -> idle`
/// Mirrors the Figma plugin's state machine: timestamp-based timing (`endAt`, polled
/// every 250ms) so a throttled/backgrounded app can't drift, and the running session
/// is persisted so it survives a quit.
enum SessionView: String, Codable {
    case idle
    case plan
    case focus
    case complete
    case breakTime
    case entireComplete
}

enum Overlay {
    case none
    case naming
    case settings
    case confirmEnd
    case confirmWrap
    case weeklyStats
}

struct DayCell: Identifiable {
    let date: Date
    let sessions: Int
    var id: Date { date }
}

struct WeekSummary {
    let sessions: Int
    let minutes: Int
    let cheese: Double
    let bestDayLabel: String?
}

@MainActor
final class TimerEngine: ObservableObject {
    @Published private(set) var view: SessionView = .idle
    @Published private(set) var paused: Bool = false
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var sessionSeconds: Int = 0
    @Published private(set) var overlay: Overlay = .none
    @Published private(set) var lastCreditLabel: String = "+1 cheese"
    @Published private(set) var lastStreakLabel: String?
    @Published private(set) var planWrappedEarly: Bool = false
    @Published private(set) var noteText: String?
    @Published private(set) var milestoneHit: Int?
    @Published private(set) var completeCountdown: Int?
    @Published private(set) var lastCompleteEarly = false
    @Published private(set) var statsHasStreakChip = false
    /// True while the clock is frozen only because a confirm modal is open (not a user pause).
    @Published private(set) var confirmFreeze = false
    @Published private(set) var breakPose: MouseSprite = .regular
    @Published private(set) var jumpCount = 0

    @Published var owned: [String]
    @Published var sceneFocusOverride: String?
    @Published var sceneBreakOverride: String?

    @Published var cheeseCount: Double
    @Published var totalSessionsCompleted: Int
    @Published var focusMinutes: Int
    @Published var breakMinutes: Int
    @Published var dailyTotal: Int
    @Published var mouseName: String
    @Published private(set) var hasNamedMouse: Bool
    @Published var compact: Bool
    @Published private(set) var showMenuBarTime: Bool
    @Published var selectedWeekStart: Date = Date()

    private var store: Store
    private var endAt: Date?
    private var pollTimer: Timer?
    private var completeTimer: Timer?
    private var breakPoseTask: DispatchWorkItem?
    private var pausedBeforeConfirm = false

    init() {
        let loaded = Store.load()
        store = loaded
        cheeseCount = loaded.cheeseCount
        totalSessionsCompleted = loaded.totalSessionsCompleted
        focusMinutes = loaded.focusMinutes
        breakMinutes = loaded.breakMinutes
        dailyTotal = loaded.dailyTotal
        mouseName = loaded.mouseName ?? "Unknown Mouse"
        hasNamedMouse = loaded.mouseName != nil
        // The naming prompt needs the full window, so never restore into compact before it.
        compact = loaded.compact && loaded.mouseName != nil
        showMenuBarTime = loaded.showMenuBarTime
        owned = loaded.owned
        sceneFocusOverride = loaded.sceneFocus
        sceneBreakOverride = loaded.sceneBreak
        restoreRunning()
        selectedWeekStart = Self.startOfWeek(containing: Date())
        startPolling()
        requestNotificationPermission()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Plan / daily progress

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        return f
    }()

    private func todayKey() -> String { Self.dayKeyFormatter.string(from: Date()) }

    private var todayStat: Store.DayStat { store.days[todayKey()] ?? Store.DayStat() }

    /// Full sessions completed today — drives the "X/Y" plan progress badge
    /// and `planComplete`. Not a separate counter: it's read straight from
    /// the per-day aggregate so it survives a quit/reopen mid-plan.
    var sessionsToday: Int { todayStat.s }
    var planComplete: Bool { sessionsToday >= dailyTotal }
    var planProgressLabel: String { "\(min(sessionsToday + 1, dailyTotal))/\(dailyTotal)" }

    /// "1 hr 25m" / "45m" — today's total focused time, for the Entire-complete screen.
    var todayDurationLabel: String { Self.formatDuration(todayStat.m) }

    /// "3" when whole, "3.5" when a half-credit from an early end is pending —
    /// cheese is fractional so an early-end's "+0.5 cheese" is truthful.
    var cheeseLabel: String { Self.formatCheese(cheeseCount) }

    static func formatCheese(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }

    /// Compact form for narrow stat columns: "45m", "1h", "1h 15m".
    static func formatDurationShort(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// What the UI shows as "paused" — a confirm modal freezing the clock doesn't count.
    var showsPaused: Bool { paused && !confirmFreeze }

    static func formatDuration(_ minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60, m = minutes % 60
            return m == 0 ? "\(h) hr" : "\(h) hr \(m)m"
        }
        return "\(minutes)m"
    }

    var todaySessionsLabel: String {
        let n = sessionsToday
        return "\(n) Session\(n == 1 ? "" : "s") complete!"
    }

    private func mutateToday(_ body: (inout Store.DayStat) -> Void) {
        var stat = todayStat
        body(&stat)
        store.days[todayKey()] = stat
        store.save()
    }

    // MARK: - Streak bonus

    /// Tunable schedule: day 2–4 of a streak -> +1, day 5–9 -> +2, day 10+ -> +3.
    private static let streakBonusSchedule: [(range: ClosedRange<Int>, bonus: Int)] = [
        (2...4, 1), (5...9, 2), (10...Int.max, 3),
    ]

    /// Consecutive local days before today that each had >= 1 full session.
    private func priorStreakLength() -> Int {
        var streak = 0
        var day = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        while let stat = store.days[Self.dayKeyFormatter.string(from: day)], stat.s > 0 {
            streak += 1
            day = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    /// Bonus for the *next* session, if it would be the first full session of
    /// today and today continues a streak. Non-punitive: missing a day just
    /// means no bonus, never a "streak broken" message.
    private func streakBonusForNextSession() -> (streakDay: Int, bonus: Int)? {
        guard sessionsToday == 0 else { return nil }
        let prior = priorStreakLength()
        guard prior >= 1 else { return nil }
        let streakDay = prior + 1
        guard let bonus = Self.streakBonusSchedule.first(where: { $0.range.contains(streakDay) })?.bonus else { return nil }
        return (streakDay, bonus)
    }

    // MARK: - Daily encouragement note

    private static let notesFirstEver = [
        "Welcome! Ready when you are.",
        "Hi there! Let's focus together.",
    ]
    private static let notesWelcomeBack = [
        "Welcome back! No rush.",
        "Good to see you again!",
    ]
    private static let notesStreak = [
        "{n}-day streak! Keep it up.",
        "Day {n} of your streak!",
    ]
    private static let notesMorning = ["Good morning! Fresh start.", "Rise and focus!"]
    private static let notesAfternoon = ["Good afternoon! Keep going.", "Halfway through the day!"]
    private static let notesEvening = ["Good evening! One more push.", "Winding down, focused up."]
    private static let notesNight = ["Night owl session!", "Quiet hours, good focus."]

    private func dayNumber() -> Int {
        Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
    }

    private func daysSinceLastFullSession() -> Int? {
        let cal = Calendar.current
        for offset in 1...30 {
            guard let day = cal.date(byAdding: .day, value: -offset, to: Date()) else { break }
            if let stat = store.days[Self.dayKeyFormatter.string(from: day)], stat.s > 0 {
                return offset
            }
        }
        return nil
    }

    private func pickNote() -> String {
        func rotate(_ pool: [String]) -> String { pool[dayNumber() % pool.count] }

        if totalSessionsCompleted == 0 {
            return rotate(Self.notesFirstEver)
        }
        if let gap = daysSinceLastFullSession(), gap >= 3 {
            return rotate(Self.notesWelcomeBack)
        }
        let prior = priorStreakLength()
        if prior >= 1 {
            return rotate(Self.notesStreak).replacingOccurrences(of: "{n}", with: "\(prior + 1)")
        }
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5...11: return rotate(Self.notesMorning)
        case 12...16: return rotate(Self.notesAfternoon)
        case 17...21: return rotate(Self.notesEvening)
        default: return rotate(Self.notesNight)
        }
    }

    /// Shown once per local day, under the mouse on the Focus screen, when the
    /// first focus session of that day starts.
    private func maybeShowNote() {
        guard store.noteDay != todayKey() else { return }
        noteText = pickNote()
        store.noteDay = todayKey()
        store.save()
    }

    func dismissNote() {
        noteText = nil
    }

    // MARK: - Weekly stats

    /// Weeks start Monday, matching the plugin's `startOfWeek`/`addDays` (DST-safe via Calendar).
    static func startOfWeek(containing date: Date) -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? date
    }

    func openWeeklyStats() {
        selectedWeekStart = Self.startOfWeek(containing: Date())
        statsHasStreakChip = statsStreakChipText != nil
        overlay = .weeklyStats
    }

    private var thisWeekStart: Date { Self.startOfWeek(containing: Date()) }
    private var oldestWeekStart: Date {
        Calendar.current.date(byAdding: .day, value: -7 * 12, to: thisWeekStart) ?? thisWeekStart
    }
    var canGoToPreviousWeek: Bool { selectedWeekStart > oldestWeekStart }
    var canGoToNextWeek: Bool { selectedWeekStart < thisWeekStart }

    /// "This week" / "Last week" / "Week of" — the plugin's titles.
    var selectedWeekTitle: String {
        if Calendar.current.isDate(selectedWeekStart, inSameDayAs: thisWeekStart) { return "This week" }
        let last = Calendar.current.date(byAdding: .day, value: -7, to: thisWeekStart) ?? thisWeekStart
        return Calendar.current.isDate(selectedWeekStart, inSameDayAs: last) ? "Last week" : "Week of"
    }

    /// Consecutive full-session days ending today (if done today) or yesterday.
    private func streakNow() -> Int { priorStreakLength() + (sessionsToday > 0 ? 1 : 0) }

    /// The plugin's streak chip under the stats numbers: shown at 2+ days, or at 1
    /// day while today's bonus is still up for grabs. Nil otherwise.
    var statsStreakChipText: String? {
        let n = streakNow()
        let done = sessionsToday > 0
        guard n >= 2 || (n >= 1 && !done) else { return nil }
        return "\(n)-day streak" + (done ? "" : " · bonus cheese ready today")
    }

    /// Popover height per screen (Figma frame heights). Static so the AppDelegate's
    /// `@Published` sinks can pass emitted values instead of reading stale state.
    static func popoverHeight(view: SessionView, overlay: Overlay, statsStreakChip: Bool) -> CGFloat {
        if overlay == .weeklyStats { return statsStreakChip ? 496 : 458 }
        switch view {
        case .idle, .plan: return 399
        case .complete: return 372
        case .entireComplete: return 392
        case .focus, .breakTime: return 440
        }
    }

    var popoverHeight: CGFloat {
        Self.popoverHeight(view: view, overlay: overlay, statsStreakChip: statsHasStreakChip)
    }

    func closeWeeklyStats() {
        overlay = .none
    }

    func selectWeek(_ weekStart: Date) {
        selectedWeekStart = weekStart
    }

    func navigateWeek(by delta: Int) {
        let cal = Calendar.current
        guard let newStart = cal.date(byAdding: .day, value: 7 * delta, to: selectedWeekStart) else { return }
        let thisWeek = Self.startOfWeek(containing: Date())
        let oldest = cal.date(byAdding: .day, value: -7 * 12, to: thisWeek) ?? thisWeek
        if newStart >= oldest && newStart <= thisWeek {
            selectedWeekStart = newStart
        }
    }

    /// 13 weeks (oldest -> newest), each Mon...Sun, for the GitHub-style heatmap.
    func heatmapWeeks() -> [[DayCell]] {
        let cal = Calendar.current
        let thisWeekStart = Self.startOfWeek(containing: Date())
        return (0...12).map { weeksAgo -> [DayCell] in
            let weekStart = cal.date(byAdding: .day, value: -7 * (12 - weeksAgo), to: thisWeekStart) ?? thisWeekStart
            return (0..<7).map { offset -> DayCell in
                let day = cal.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                let stat = store.days[Self.dayKeyFormatter.string(from: day)]
                return DayCell(date: day, sessions: stat?.s ?? 0)
            }
        }
    }

    func summary(for weekStart: Date) -> WeekSummary {
        let cal = Calendar.current
        var sessions = 0, minutes = 0
        var cheese = 0.0
        var best: (date: Date, sessions: Int)?
        for offset in 0..<7 {
            let day = cal.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            guard let stat = store.days[Self.dayKeyFormatter.string(from: day)] else { continue }
            sessions += stat.s
            minutes += stat.m
            cheese += stat.c
            if stat.s > 0, stat.s > (best?.sessions ?? 0) {
                best = (day, stat.s)
            }
        }
        var bestLabel: String?
        if let best {
            let f = DateFormatter()
            f.dateFormat = "EEE"
            bestLabel = "Best day: \(f.string(from: best.date)) · \(best.sessions)"
        }
        return WeekSummary(sessions: sessions, minutes: minutes, cheese: cheese, bestDayLabel: bestLabel)
    }

    // MARK: - Scenes & shop

    var level: Int { SceneCatalog.level(for: totalSessionsCompleted) }

    /// `activeScene(slot)`: manual choice (if owned) -> an owned holiday set
    /// inside its date window -> basic (office evolution / seasonal park).
    func activeScene(_ slot: SceneSlot) -> String {
        let override = slot == .focus ? sceneFocusOverride : sceneBreakOverride
        if let override, owned.contains(override) {
            return override
        }
        if let holiday = SceneCatalog.activeHoliday() {
            if let item = SceneCatalog.shopItems.first(where: { $0.holiday == holiday && $0.slot == slot }),
               owned.contains(item.id) {
                return item.id
            }
        }
        return slot == .focus ? SceneCatalog.basicOfficeScene(level: level) : SceneCatalog.basicBreakScene()
    }

    func isOwned(_ item: ShopItem) -> Bool { owned.contains(item.id) }
    func isUnlocked(_ item: ShopItem) -> Bool { level >= item.unlockLevel }

    /// Buying spends cheese immediately and starts using the scene right away
    /// (matches the plugin: purchases only ever spend cheese, nothing expires).
    func purchase(_ item: ShopItem) {
        guard !isOwned(item), isUnlocked(item), cheeseCount >= Double(SceneCatalog.price) else { return }
        cheeseCount -= Double(SceneCatalog.price)
        owned.append(item.id)
        setScene(item.id, slot: item.slot)
        persistCounts()
    }

    func setScene(_ id: String?, slot: SceneSlot) {
        if slot == .focus {
            sceneFocusOverride = id
        } else {
            sceneBreakOverride = id
        }
        persistCounts()
    }

    // MARK: - Complete screen auto-advance

    /// The Complete screen has no manual "Start Break" button in the Figma
    /// design — it auto-advances after a countdown ("Starting your break
    /// automatically in 5s…"). Tapping the countdown text skips the wait.
    private static let completeCountdownSeconds = 5

    private func startCompleteCountdown() {
        completeTimer?.invalidate()
        completeCountdown = Self.completeCountdownSeconds
        completeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickCompleteCountdown() }
        }
    }

    private func tickCompleteCountdown() {
        guard let remaining = completeCountdown else { return }
        if remaining <= 1 {
            stopCompleteCountdown()
            if view == .complete { startBreak() }
        } else {
            completeCountdown = remaining - 1
        }
    }

    private func stopCompleteCountdown() {
        completeTimer?.invalidate()
        completeTimer = nil
        completeCountdown = nil
    }

    // MARK: - Break interactions (shared by the full view and the compact strip)

    private func resetBreakPose() {
        breakPoseTask?.cancel()
        breakPose = .regular
    }

    private func setBreakPose(_ pose: MouseSprite, for seconds: TimeInterval) {
        breakPoseTask?.cancel()
        breakPose = pose
        let task = DispatchWorkItem { [weak self] in self?.breakPose = .regular }
        breakPoseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: task)
    }

    private var canInteract: Bool { view == .breakTime && !paused }

    /// Tap the mouse: hop for 650ms (restarts on every tap, cancels dancing).
    func jump() {
        guard canInteract else { return }
        jumpCount += 1
        setBreakPose(.jumping, for: 0.65)
    }

    /// "Feed for a snack": feeding pose for 3s.
    func feed() {
        guard canInteract else { return }
        setBreakPose(.feeding, for: 3.0)
    }

    /// Cursor moving over the screen: dance, stopping 700ms after the last move.
    func breakCursorMoved() {
        guard canInteract, breakPose != .jumping, breakPose != .feeding else { return }
        setBreakPose(.dancing, for: 0.7)
    }

    func breakCursorLeft() {
        if breakPose == .dancing { resetBreakPose() }
    }

    // MARK: - Menu bar timer

    func setShowMenuBarTime(_ on: Bool) {
        showMenuBarTime = on
        persistCounts()
    }

    /// The remaining time shown next to the menu bar icon — only while a Focus
    /// or Break session is running (or paused), and only if the user left it on.
    /// Nil hides it entirely (Idle, Plan, Complete, Entire-complete).
    /// Static (taking the values as arguments) because it's driven from `@Published`
    /// sinks, which fire *before* the property changes.
    static func menuBarTimeText(view: SessionView, remaining: TimeInterval, enabled: Bool) -> String? {
        guard enabled, view == .focus || view == .breakTime else { return nil }
        let total = max(0, Int(remaining.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - Compact mode

    /// Compact Idle's primary button: Plan has no compact layout, so expand first.
    func expandAndPlan() {
        compact = false
        persistCounts()
        tapPlanButton()
    }


    func toggleCompact() {
        // Plan has no compact layout (the plugin disables Minimize there too).
        if !compact, view == .plan { return }
        compact.toggle()
        if compact, overlay == .weeklyStats { overlay = .none }
        persistCounts()
    }

    // MARK: - Transitions

    /// Idle's "Plan your sessions" button: gates on the one-time naming prompt first.
    func tapPlanButton() {
        if hasNamedMouse {
            view = .plan
        } else {
            overlay = .naming
        }
    }

    func confirmName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mouseName = trimmed
        hasNamedMouse = true
        persistCounts()
        overlay = .none
        view = .plan
    }

    /// Bounds match the Figma plugin's (Daily total 1–20, Focus 1–90, Break 1–30).
    func startPlan(dailyTotal newTotal: Int, focusMinutes newFocus: Int, breakMinutes newBreak: Int) {
        dailyTotal = min(max(newTotal, 1), 20)
        focusMinutes = min(max(newFocus, 1), 90)
        breakMinutes = min(max(newBreak, 1), 30)
        persistCounts()
        startFocus()
    }

    func startFocus() {
        begin(.focus, minutes: focusMinutes)
        maybeShowNote()
    }

    func startBreak() {
        stopCompleteCountdown()
        begin(.breakTime, minutes: breakMinutes)
    }

    func togglePause() {
        guard view == .focus || view == .breakTime else { return }
        if paused {
            // Resume: re-derive endAt from the frozen remaining time.
            endAt = Date().addingTimeInterval(remaining)
            paused = false
        } else {
            remaining = max(0, endAt?.timeIntervalSinceNow ?? 0)
            paused = true
        }
        persistRunning()
    }

    /// "End session early" (Focus only) — credits half a session's worth of
    /// effort, then still shows the Complete screen before Break, same as a
    /// natural finish, just with a smaller credit (matches the plugin: no
    /// penalty either way, a little credit either way).
    func endEarly() {
        let minutesElapsed = minutesElapsedInCurrentSession()
        cheeseCount += 0.5
        mutateToday { $0.m += minutesElapsed; $0.c += 0.5 }
        persistCounts()
        lastCreditLabel = "+0.5 cheese"
        lastCompleteEarly = true
        lastStreakLabel = nil
        milestoneHit = nil
        noteText = nil
        view = .complete
        paused = false
        remaining = 0
        sessionSeconds = 0
        endAt = nil
        persistRunning()
        startCompleteCountdown()
    }

    /// Break finishing (naturally or via Skip) auto-chains into the next Focus
    /// if today's plan isn't done yet, else shows Entire-complete.
    func skipBreak() {
        afterBreak()
    }

    func openSettings() {
        overlay = .settings
    }

    func closeSettings() {
        overlay = .none
    }

    /// Opens the "End this session?" confirm, freezing the clock (matches the
    /// Figma plugin: no penalty either way, a little credit either way).
    func openConfirmEnd() {
        freezeForConfirm()
        overlay = .confirmEnd
    }

    /// Opens the "Wrap up today" confirm — same freeze mechanism, different copy/action.
    func openConfirmWrap() {
        freezeForConfirm()
        overlay = .confirmWrap
    }

    /// "Keep going" — resumes the clock if it was running before the confirm opened.
    func dismissConfirm() {
        confirmFreeze = false
        overlay = .none
        if !pausedBeforeConfirm {
            paused = false
            endAt = Date().addingTimeInterval(remaining)
            persistRunning()
        }
    }

    func confirmEndSession() {
        confirmFreeze = false
        overlay = .none
        endEarly()
    }

    /// Ends the entire day's plan right now: 0.5 credit if mid-Focus (break
    /// never earned any), then straight to Entire-complete — no per-cycle
    /// Complete screen in between.
    func confirmWrapUp() {
        confirmFreeze = false
        overlay = .none
        if view == .focus {
            let minutesElapsed = minutesElapsedInCurrentSession()
            cheeseCount += 0.5
            mutateToday { $0.m += minutesElapsed; $0.c += 0.5 }
            persistCounts()
        }
        noteText = nil
        showEntireComplete(early: true)
    }

    /// Entire-complete's second button: "Resume sessions" if wrapped up early
    /// (same dailyTotal, just continues) or "Add more sessions" otherwise
    /// (bumps dailyTotal by 1), then starts the next Focus either way.
    func continueFromEntireComplete() {
        if !planWrappedEarly {
            dailyTotal = min(dailyTotal + 1, 20)
            persistCounts()
        }
        startFocus()
    }

    private func minutesElapsedInCurrentSession() -> Int {
        max(0, (sessionSeconds - Int(remaining.rounded())) / 60)
    }

    private func freezeForConfirm() {
        pausedBeforeConfirm = paused
        confirmFreeze = !paused
        if !paused {
            remaining = max(0, endAt?.timeIntervalSinceNow ?? 0)
            paused = true
            persistRunning()
        }
    }

    /// Bounds match the Figma plugin's (Daily total 1–20, Focus 1–90, Break 1–30).
    /// Settings and Plan are two views onto the exact same three store fields.
    func updateSettings(dailyTotal newTotal: Int, focusMinutes newFocus: Int, breakMinutes newBreak: Int) {
        dailyTotal = min(max(newTotal, 1), 20)
        focusMinutes = min(max(newFocus, 1), 90)
        breakMinutes = min(max(newBreak, 1), 30)
        persistCounts()
    }

    // MARK: - Internal

    private func begin(_ next: SessionView, minutes: Int) {
        resetBreakPose()
        sessionSeconds = minutes * 60
        remaining = TimeInterval(sessionSeconds)
        endAt = Date().addingTimeInterval(remaining)
        paused = false
        view = next
        persistRunning()
    }

    private func afterBreak() {
        if planComplete {
            showEntireComplete(early: false)
        } else {
            startFocus()
        }
    }

    private func showEntireComplete(early: Bool) {
        resetBreakPose()
        planWrappedEarly = early
        view = .entireComplete
        paused = false
        remaining = 0
        sessionSeconds = 0
        endAt = nil
        persistRunning()
    }

    private func goIdle() {
        resetBreakPose()
        view = .idle
        paused = false
        remaining = 0
        sessionSeconds = 0
        endAt = nil
        persistRunning()
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard !paused, let endAt else { return }
        let left = endAt.timeIntervalSinceNow
        if left <= 0 {
            remaining = 0
            finishSession()
        } else {
            remaining = left
        }
    }

    private func finishSession() {
        if overlay == .weeklyStats { overlay = .none }
        switch view {
        case .focus:
            let streak = streakBonusForNextSession()
            let bonus = streak?.bonus ?? 0
            cheeseCount += Double(1 + bonus)
            totalSessionsCompleted += 1
            mutateToday { $0.s += 1; $0.m += focusMinutes; $0.c += Double(1 + bonus) }
            persistCounts()
            lastCreditLabel = bonus > 0 ? "+\(1 + bonus) cheese" : "+1 cheese"
            lastCompleteEarly = false
            lastStreakLabel = streak.map { "\($0.streakDay)-day streak! +\($0.bonus) bonus" }
            milestoneHit = SceneCatalog.milestones.contains(totalSessionsCompleted) ? totalSessionsCompleted : nil
            noteText = nil
            view = .complete
            endAt = nil
            persistRunning()
            startCompleteCountdown()
            notify(title: "Focus session complete!", body: "+1 🧀 — time for a break.")
        case .breakTime:
            notify(title: "Break's over", body: "Ready for another focus session?")
            afterBreak()
        default:
            break
        }
    }

    // MARK: - Persistence

    private func persistCounts() {
        store.cheeseCount = cheeseCount
        store.totalSessionsCompleted = totalSessionsCompleted
        store.focusMinutes = focusMinutes
        store.breakMinutes = breakMinutes
        store.dailyTotal = dailyTotal
        // Only persist once actually named — otherwise saving from some other
        // action (e.g. Settings) before naming would write the "Unknown Mouse"
        // placeholder as a real (non-nil) name, falsely skipping the naming
        // prompt on the next launch.
        if hasNamedMouse { store.mouseName = mouseName }
        store.compact = compact
        store.showMenuBarTime = showMenuBarTime
        store.owned = owned
        store.sceneFocus = sceneFocusOverride
        store.sceneBreak = sceneBreakOverride
        store.save()
    }

    private func persistRunning() {
        store.focusMinutes = focusMinutes
        store.breakMinutes = breakMinutes
        store.dailyTotal = dailyTotal
        if (view == .focus || view == .breakTime), let endAt {
            store.running = Store.RunningState(
                view: view,
                paused: paused,
                endAt: endAt,
                remaining: remaining,
                sessionSeconds: sessionSeconds
            )
        } else {
            store.running = nil
        }
        store.save()
    }

    private func restoreRunning() {
        guard let running = store.running else { return }
        sessionSeconds = running.sessionSeconds
        paused = running.paused

        if running.paused {
            remaining = running.remaining
            endAt = Date().addingTimeInterval(running.remaining)
            view = running.view
        } else if running.endAt > Date() {
            endAt = running.endAt
            remaining = running.endAt.timeIntervalSinceNow
            view = running.view
        } else {
            // Session finished while the app was closed — credit it now rather
            // than silently dropping it (matches the plugin's non-punitive stance).
            view = running.view
            endAt = running.endAt
            remaining = 0
            finishSession()
        }
    }
}
