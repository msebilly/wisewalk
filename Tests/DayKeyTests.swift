import Testing
import Foundation
@testable import WiseWalk

/// 由「本地墙上时间 + 时区偏移」构造一个绝对时刻，让测试意图一目了然。
private func instant(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, tzMinutes: Int) -> Date {
    var c = DateComponents()
    c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: tzMinutes * 60)!
    return cal.date(from: c)!
}

@Test func 北京时间正午归当日() {
    let t = instant(2026, 7, 28, 12, 0, tzMinutes: 480)
    #expect(DayKey.make(from: t, tzOffsetMinutes: 480) == 20260728)
}

@Test func 同一时刻在不同时区属于不同日期() {
    // 北京 7月28日 08:00 == 温哥华 7月27日 17:00
    let t = instant(2026, 7, 28, 8, 0, tzMinutes: 480)
    #expect(DayKey.make(from: t, tzOffsetMinutes: 480) == 20260728)
    #expect(DayKey.make(from: t, tzOffsetMinutes: -420) == 20260727)
}

@Test func 一日起始设为凌晨三点时两点半算前一天() {
    let t = instant(2026, 7, 28, 2, 30, tzMinutes: 480)
    #expect(DayKey.make(from: t, tzOffsetMinutes: 480, dayStartHour: 3) == 20260727)
}

@Test func 一日起始设为凌晨三点时三点整算当天() {
    let t = instant(2026, 7, 28, 3, 0, tzMinutes: 480)
    #expect(DayKey.make(from: t, tzOffsetMinutes: 480, dayStartHour: 3) == 20260728)
}

@Test func 一日起始为零点时凌晨两点半算当天() {
    let t = instant(2026, 7, 28, 2, 30, tzMinutes: 480)
    #expect(DayKey.make(from: t, tzOffsetMinutes: 480) == 20260728)
}

@Test func 跨月回退() {
    let t = instant(2026, 7, 1, 1, 0, tzMinutes: 480)
    #expect(DayKey.make(from: t, tzOffsetMinutes: 480, dayStartHour: 3) == 20260630)
}

@Test func 跨年回退() {
    let t = instant(2026, 1, 1, 1, 0, tzMinutes: 480)
    #expect(DayKey.make(from: t, tzOffsetMinutes: 480, dayStartHour: 3) == 20251231)
}

@Test func 闰日() {
    let t = instant(2028, 2, 29, 10, 0, tzMinutes: 480)
    #expect(DayKey.make(from: t, tzOffsetMinutes: 480) == 20280229)
}

@Test func 半小时时区() {
    // 印度 +330。当地 7月28日 00:15 == UTC 7月27日 18:45
    let t = instant(2026, 7, 28, 0, 15, tzMinutes: 330)
    #expect(DayKey.make(from: t, tzOffsetMinutes: 330) == 20260728)
    #expect(DayKey.make(from: t, tzOffsetMinutes: 0) == 20260727)
}

@Test func 反解出年月日() {
    let p = DayKey.decompose(20260728)
    #expect(p.year == 2026)
    #expect(p.month == 7)
    #expect(p.day == 28)
}

@Test func 取当前时区偏移() {
    let tz = TimeZone(identifier: "Asia/Shanghai")!
    #expect(DayKey.currentOffsetMinutes(at: Date(), timeZone: tz) == 480)
}

@Test func 今日键使用指定时区与时刻() {
    let tz = TimeZone(identifier: "Asia/Shanghai")!
    let t = instant(2026, 7, 28, 23, 59, tzMinutes: 480)
    #expect(DayKey.today(now: t, timeZone: tz) == 20260728)
}
