import Foundation

/// 日期键：yyyyMMdd 的整数表示。2026-07-28 → 20260728。
///
/// **为什么不直接存 Date**：CloudKit 同步来的记录可能出自任何时区的设备，
/// 从 UTC 时间戳反推「那天是几号」必须知道记录产生**当时**的本地偏移。
/// 所以每笔流水都随身携带 tzOffsetMinutes，而 dayKey 一旦写入就永不重算——
/// 用户从北京飞到温哥华，昨天的功课不该跳到前天去。
enum DayKey {
    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    /// 由绝对时刻计算日期键。
    /// - Parameters:
    ///   - date: 绝对时刻
    ///   - tzOffsetMinutes: 该时刻的本地时区偏移，东八区为 480，西七区为 -420
    ///   - dayStartHour: 一日起始小时。设为 3 则凌晨 2:59 仍算前一天
    static func make(from date: Date, tzOffsetMinutes: Int, dayStartHour: Int = 0) -> Int {
        let shifted = date.timeIntervalSince1970
            + Double(tzOffsetMinutes * 60)
            - Double(dayStartHour * 3600)
        let c = utcCalendar.dateComponents(
            [.year, .month, .day],
            from: Date(timeIntervalSince1970: shifted)
        )
        // 公历日历请求年月日必定返回三者，此处不可能为 nil。
        return c.year! * 10000 + c.month! * 100 + c.day!
    }

    /// 按指定时区计算「今天」。
    static func today(
        dayStartHour: Int = 0,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) -> Int {
        make(
            from: now,
            tzOffsetMinutes: currentOffsetMinutes(at: now, timeZone: timeZone),
            dayStartHour: dayStartHour
        )
    }

    /// 写入流水时随身记录的时区偏移（分钟）。
    static func currentOffsetMinutes(at date: Date = Date(), timeZone: TimeZone = .current) -> Int {
        timeZone.secondsFromGMT(for: date) / 60
    }

    /// 反解为年月日，供月历与显示使用。
    static func decompose(_ key: Int) -> (year: Int, month: Int, day: Int) {
        (key / 10000, (key / 100) % 100, key % 100)
    }
}
