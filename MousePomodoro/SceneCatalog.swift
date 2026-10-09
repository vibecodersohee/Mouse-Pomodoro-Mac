import Foundation

enum SceneSlot: String, Codable {
    case focus
    case breakTime
}

enum HolidaySeason: String {
    case easter, halloween, christmas
}

struct ShopItem: Identifiable {
    let id: String          // also the scene asset name ("scene-<id>" in Assets.xcassets)
    let name: String
    let slot: SceneSlot
    let unlockLevel: Int     // 1 = ungated
    let holiday: HolidaySeason?
}

/// Everything about scene selection (evolution level, season, holidays) and
/// the shop catalog, ported from the Figma plugin's `basicScene`/`activeScene`/
/// shop rules (see DEV-LOG "Scenes, seasons & the background shop").
enum SceneCatalog {
    static let price = 20

    /// `LEVEL_AT` — highest level whose threshold is <= totalSessionsCompleted.
    static let levelThresholds = [0, 10, 50, 250, 1000]

    static func level(for totalSessionsCompleted: Int) -> Int {
        var lvl = 1
        for (index, threshold) in levelThresholds.enumerated() where totalSessionsCompleted >= threshold {
            lvl = index + 1
        }
        return lvl
    }

    static let milestones = [10, 25, 50, 100, 250, 500, 1000]

    /// Milestones without dedicated art reuse m10, matching the product owner's instruction.
    static func milestoneArt(for n: Int) -> String {
        [10, 50, 100].contains(n) ? "m\(n)" : "m10"
    }

    static func isLevelUpMilestone(_ n: Int) -> Bool { levelThresholds.contains(n) }

    static func milestoneCopy(for n: Int) -> String {
        switch n {
        case 10: return "Double digits! You're building a real habit."
        case 25: return "25 sessions — steady and strong."
        case 50: return "50 sessions! Halfway to triple digits."
        case 100: return "Triple digits! That's serious focus."
        case 250: return "250 sessions — remarkable consistency."
        case 500: return "500 sessions. Truly impressive."
        case 1000: return "1000 sessions! Legendary focus."
        default: return "Another milestone reached!"
        }
    }

    static let shopItems: [ShopItem] = [
        ShopItem(id: "studio-green", name: "Green Studio", slot: .breakTime, unlockLevel: 1, holiday: nil),
        ShopItem(id: "studio-pink", name: "Pink Studio", slot: .breakTime, unlockLevel: 1, holiday: nil),
        ShopItem(id: "break-terrace", name: "Rooftop", slot: .breakTime, unlockLevel: 2, holiday: nil),
        ShopItem(id: "break-room", name: "Cafeteria", slot: .breakTime, unlockLevel: 2, holiday: nil),
        ShopItem(id: "break-washroom", name: "Washroom", slot: .breakTime, unlockLevel: 2, holiday: nil),
        ShopItem(id: "easter-park", name: "Easter", slot: .breakTime, unlockLevel: 3, holiday: .easter),
        ShopItem(id: "halloween-park", name: "Halloween", slot: .breakTime, unlockLevel: 3, holiday: .halloween),
        ShopItem(id: "christmas-park", name: "Christmas", slot: .breakTime, unlockLevel: 3, holiday: .christmas),
    ]

    /// Sessions needed to reach `level` (the "Unlocks at level N · X sessions" line).
    static func sessionsRequired(forLevel level: Int) -> Int {
        levelThresholds[min(max(level, 1), levelThresholds.count) - 1]
    }

    /// The date window a holiday scene shows up on its own, e.g. "Oct 15 – Nov 1".
    static func windowLabel(for holiday: HolidaySeason, on date: Date = Date()) -> String {
        switch holiday {
        case .christmas: return "Dec 1 – Jan 5"
        case .halloween: return "Oct 15 – Nov 1"
        case .easter:
            let cal = Calendar.current
            let year = cal.component(.year, from: date)
            guard let easter = computusEaster(year: year),
                  let start = cal.date(byAdding: .day, value: -14, to: easter),
                  let end = cal.date(byAdding: .day, value: 6, to: easter) else { return "Around Easter" }
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return "\(f.string(from: start)) – \(f.string(from: end))"
        }
    }

    // MARK: - Basic scenes (office evolution + seasonal park)

    static func basicOfficeScene(level: Int) -> String {
        level <= 1 ? "office" : "office-l\(min(level, 5))"
    }

    static func basicBreakScene(date: Date = Date()) -> String {
        "park-\(season(for: date))"
    }

    // MARK: - Season / hemisphere

    /// IANA timezones in the southern hemisphere — anything unlisted is treated as north.
    private static func isSouthernHemisphere() -> Bool {
        let tz = TimeZone.current.identifier
        let southernPrefixes = [
            "Australia/", "Pacific/Auckland", "Pacific/Chatham", "Antarctica/",
            "Africa/Johannesburg", "Africa/Maputo", "Africa/Windhoek", "Africa/Gaborone",
            "America/Sao_Paulo", "America/Argentina", "America/Santiago", "America/Lima",
            "America/La_Paz", "America/Asuncion", "America/Montevideo",
            "Indian/Antananarivo", "Indian/Mauritius",
        ]
        return southernPrefixes.contains { tz.hasPrefix($0) }
    }

    /// Meteorological seasons (Mar-May spring, Jun-Aug summer, Sep-Nov fall, Dec-Feb
    /// winter), flipped 6 months in the southern hemisphere.
    static func season(for date: Date) -> String {
        let month = Calendar.current.component(.month, from: date)
        func northern(_ m: Int) -> String {
            switch m {
            case 3, 4, 5: return "spring"
            case 6, 7, 8: return "summer"
            case 9, 10, 11: return "fall"
            default: return "winter"
            }
        }
        let base = northern(month)
        guard isSouthernHemisphere() else { return base }
        switch base {
        case "spring": return "fall"
        case "summer": return "winter"
        case "fall": return "spring"
        default: return "summer"
        }
    }

    // MARK: - Holiday windows (local dates, hemisphere-independent)

    static func activeHoliday(on date: Date = Date()) -> HolidaySeason? {
        let cal = Calendar.current
        let year = cal.component(.year, from: date)

        if let decStart = cal.date(from: DateComponents(year: year, month: 12, day: 1)), date >= decStart {
            return .christmas
        }
        if let janEnd = cal.date(from: DateComponents(year: year, month: 1, day: 5)), date <= janEnd {
            return .christmas
        }
        if let octStart = cal.date(from: DateComponents(year: year, month: 10, day: 15)),
           let novEnd = cal.date(from: DateComponents(year: year, month: 11, day: 1)),
           date >= octStart, date <= novEnd {
            return .halloween
        }
        if let easter = computusEaster(year: year) {
            let start = cal.date(byAdding: .day, value: -14, to: easter) ?? easter
            let end = cal.date(byAdding: .day, value: 6, to: easter) ?? easter
            if date >= start, date <= end { return .easter }
        }
        return nil
    }

    /// Anonymous Gregorian algorithm for the date of Easter Sunday.
    private static func computusEaster(year: Int) -> Date? {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }
}
