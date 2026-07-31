import Testing
import Foundation
@testable import WiseWalk

private let 北京时间 = TimeZone(identifier: "Asia/Shanghai")!
private let 温哥华 = TimeZone(identifier: "America/Vancouver")!

private func 时刻(_ tz: TimeZone, _ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
    var c = DateComponents()
    c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    return cal.date(from: c)!
}

@Test func 日历日期转dayKey按所在时区的日历页() {
    // 日期选择器给的是「用户在日历上点的那一格」，与一日起始时间无关。
    #expect(DayKey.fromCalendarDate(时刻(北京时间, 2026, 7, 1, 0, 30), timeZone: 北京时间) == 20260701)
    #expect(DayKey.fromCalendarDate(时刻(北京时间, 2026, 7, 1, 23, 30), timeZone: 北京时间) == 20260701)
    #expect(DayKey.fromCalendarDate(时刻(北京时间, 2026, 12, 31, 12, 0), timeZone: 北京时间) == 20261231)
}

@Test func 同一绝对时刻在不同时区落在不同日历页() {
    let t = 时刻(北京时间, 2026, 7, 1, 8, 0)   // 北京 7/1 早八点 = 温哥华 6/30 下午五点
    #expect(DayKey.fromCalendarDate(t, timeZone: 北京时间) == 20260701)
    #expect(DayKey.fromCalendarDate(t, timeZone: 温哥华) == 20260630)
}

@Test func dayKey转回日期取当地正午() {
    // 取正午而不是零点，是为了远离夏令时切换点——
    // 某些时区的某些日子零点根本不存在，构造出来会是 nil 或跳到前一天。
    let d = DayKey.calendarDate(of: 20260701, timeZone: 北京时间)
    #expect(d != nil)
    #expect(DayKey.fromCalendarDate(d!, timeZone: 北京时间) == 20260701)
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = 北京时间
    #expect(cal.component(.hour, from: d!) == 12)
}

@Test func dayKey与日期能来回转不丢失() {
    for key in [20240229, 20251231, 20260101, 20260701, 20261130] {
        let d = DayKey.calendarDate(of: key, timeZone: 北京时间)
        #expect(d != nil, "\(key) 转不出日期")
        #expect(DayKey.fromCalendarDate(d!, timeZone: 北京时间) == key)
    }
}

@Test func 非法dayKey转不出日期() {
    #expect(DayKey.calendarDate(of: 20260231, timeZone: 北京时间) == nil, "2 月 31 号不存在")
    #expect(DayKey.calendarDate(of: 20261340, timeZone: 北京时间) == nil)
    #expect(DayKey.calendarDate(of: 0, timeZone: 北京时间) == nil)
}

@Test func 能判断是不是未来() {
    #expect(DayKey.isFuture(20260729, comparedTo: 20260728))
    #expect(!DayKey.isFuture(20260728, comparedTo: 20260728))
    #expect(!DayKey.isFuture(20260101, comparedTo: 20260728))
}
