import Foundation

/// `DayKey` 与日历日期的互转。补记页的日期选择器要用。
///
/// **与 `DayKey.make(from:tzOffsetMinutes:dayStartHour:)` 不是一回事**：
/// 那个回答的是「这个绝对时刻，按用户设的一日起始，算哪一天」；
/// 这里回答的是「用户在日历上点的那一格是哪一天」。
/// 补记时用户点的是日历格子，跟他把一日起始设成几点没有关系。
extension DayKey {
    private static func gregorian(_ timeZone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    /// 日历上的某一天 → dayKey。
    static func fromCalendarDate(_ date: Date, timeZone: TimeZone = .current) -> Int {
        let c = gregorian(timeZone).dateComponents([.year, .month, .day], from: date)
        // 公历日历请求年月日必定返回三者。
        return c.year! * 10000 + c.month! * 100 + c.day!
    }

    /// dayKey → 该日**当地正午**的时刻。日期选择器回填用。
    ///
    /// 取正午而不是零点：某些时区的某些日子（夏令时切换日）零点根本不存在，
    /// 构造出来会是 nil，或被日历悄悄挪到前一天。正午离任何切换点都足够远。
    /// 日期非法（如 2 月 31 号）返回 nil。
    static func calendarDate(of dayKey: Int, timeZone: TimeZone = .current) -> Date? {
        let parts = decompose(dayKey)
        guard parts.month >= 1, parts.month <= 12, parts.day >= 1, parts.day <= 31 else { return nil }
        var comps = DateComponents()
        comps.year = parts.year
        comps.month = parts.month
        comps.day = parts.day
        comps.hour = 12
        let cal = gregorian(timeZone)
        guard let date = cal.date(from: comps) else { return nil }
        // `Calendar.date(from:)` 会把 2 月 31 号顺延成 3 月 3 号而不是报错，
        // 所以转回去比一遍，对不上就判非法。
        guard fromCalendarDate(date, timeZone: timeZone) == dayKey else { return nil }
        return date
    }

    /// 补记不许记到未来——明天的功课还没做。
    static func isFuture(_ dayKey: Int, comparedTo today: Int) -> Bool {
        dayKey > today
    }
}
