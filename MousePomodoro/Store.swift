import Foundation

/// Persisted state, mirroring the Figma plugin's `clientStorage` schema (schema v2),
/// scoped down to what the core timer loop needs for now.
///
/// Loaded with a custom `init(from:)` that defaults every missing/mistyped key
/// instead of failing the whole decode — the plugin's `Object.assign(defaults,
/// saved)` pattern. Swift's synthesized `Decodable` would instead require every
/// non-optional field to be present, so adding a field here would silently
/// reset an existing user's entire save the moment it shipped.
struct Store: Codable {
    var mouseName: String?
    var cheeseCount: Double = 0
    var totalSessionsCompleted: Int = 0
    var focusMinutes: Int = 25
    var breakMinutes: Int = 5
    var dailyTotal: Int = 1
    var days: [String: DayStat] = [:]
    var noteDay: String?
    var compact: Bool = false
    var showMenuBarTime: Bool = true
    var owned: [String] = []
    var sceneFocus: String?
    var sceneBreak: String?
    var running: RunningState?

    init() {}

    /// Per-local-day aggregate (keyed "yyyy-MM-dd") — enough for plan progress,
    /// the entire-complete summary, and (later) weekly stats/streaks.
    struct DayStat: Codable {
        var s: Int = 0      // full sessions completed
        var m: Int = 0      // minutes focused
        var c: Double = 0   // cheese credit earned (stats only, not currency)

        private enum CodingKeys: String, CodingKey { case s, m, c }

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            s = try c.decodeIfPresent(Int.self, forKey: .s) ?? 0
            m = try c.decodeIfPresent(Int.self, forKey: .m) ?? 0
            self.c = try c.decodeIfPresent(Double.self, forKey: .c) ?? 0
        }
    }

    struct RunningState: Codable {
        var view: SessionView
        var paused: Bool
        var endAt: Date
        var remaining: TimeInterval
        var sessionSeconds: Int
    }

    private enum CodingKeys: String, CodingKey {
        case mouseName, cheeseCount, totalSessionsCompleted, focusMinutes, breakMinutes
        case dailyTotal, days, noteDay, compact, showMenuBarTime, owned, sceneFocus, sceneBreak, running
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mouseName = try c.decodeIfPresent(String.self, forKey: .mouseName)
        cheeseCount = try c.decodeIfPresent(Double.self, forKey: .cheeseCount) ?? 0
        totalSessionsCompleted = try c.decodeIfPresent(Int.self, forKey: .totalSessionsCompleted) ?? 0
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 25
        breakMinutes = try c.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? 5
        dailyTotal = try c.decodeIfPresent(Int.self, forKey: .dailyTotal) ?? 1
        days = try c.decodeIfPresent([String: DayStat].self, forKey: .days) ?? [:]
        noteDay = try c.decodeIfPresent(String.self, forKey: .noteDay)
        compact = try c.decodeIfPresent(Bool.self, forKey: .compact) ?? false
        showMenuBarTime = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarTime) ?? true
        owned = try c.decodeIfPresent([String].self, forKey: .owned) ?? []
        sceneFocus = try c.decodeIfPresent(String.self, forKey: .sceneFocus)
        sceneBreak = try c.decodeIfPresent(String.self, forKey: .sceneBreak)
        running = try c.decodeIfPresent(RunningState.self, forKey: .running)
    }

    private static let defaultsKey = "mousePomodoroState"

    static func load() -> Store {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return Store() }
        do {
            return try JSONDecoder().decode(Store.self, from: data)
        } catch {
            // Never silently wipe a save we can't fully parse — surface it so a
            // real decode regression gets caught instead of looking like data loss.
            assertionFailure("Store decode failed, falling back to defaults: \(error)")
            return Store()
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
