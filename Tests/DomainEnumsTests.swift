import Testing
@testable import WiseWalk

@Test func 计量方式原始值稳定() {
    #expect(MeasureType.count.rawValue == "count")
    #expect(MeasureType.duration.rawValue == "duration")
    #expect(MeasureType.check.rawValue == "check")
    #expect(MeasureType.allCases.count == 3)
}

@Test func 流水来源原始值稳定() {
    #expect(SessionSource.counter.rawValue == "counter")
    #expect(SessionSource.timer.rawValue == "timer")
    #expect(SessionSource.manual.rawValue == "manual")
    #expect(SessionSource.adjustment.rawValue == "adjustment")
    #expect(SessionSource.allCases.count == 4)
}

@Test func 排班规则往返() {
    let cases: [ScheduleRule] = [
        .daily,
        .weekdays([1, 3, 5]),
        .lunarDays([1, 15]),
        .lunarSixZhai,
        .lunarTenZhai,
        .lunarBuddhaDays
    ]
    for rule in cases {
        #expect(ScheduleRule(rawValue: rule.rawValue) == rule, "往返失败：\(rule.rawValue)")
    }
}

@Test func 排班规则原始值格式固定() {
    #expect(ScheduleRule.daily.rawValue == "daily")
    #expect(ScheduleRule.weekdays([5, 1, 3]).rawValue == "weekdays:1,3,5")
    #expect(ScheduleRule.lunarDays([15, 1]).rawValue == "lunar:1,15")
    #expect(ScheduleRule.lunarSixZhai.rawValue == "lunar:sixzhai")
    #expect(ScheduleRule.lunarTenZhai.rawValue == "lunar:tenzhai")
    #expect(ScheduleRule.lunarBuddhaDays.rawValue == "lunar:buddhaDays")
}

@Test func 无法识别的排班退化为每日() {
    #expect(ScheduleRule(rawValue: "") == .daily)
    #expect(ScheduleRule(rawValue: "未来版本的新规则") == .daily)
    #expect(ScheduleRule(rawValue: "weekdays:") == .daily)
    #expect(ScheduleRule(rawValue: "lunar:") == .daily)
    #expect(ScheduleRule(rawValue: "weekdays:abc") == .daily)
}

@Test func 计量方式非法值解析为空() {
    // 退化为 .count 发生在 PracticeItem.measureType 的读取门面上，不在这里
    #expect(MeasureType(rawValue: "unknown") == nil)
}
