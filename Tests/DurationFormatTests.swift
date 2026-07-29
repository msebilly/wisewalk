import Testing
@testable import WiseWalk

@Test func 时钟格式分秒() {
    #expect(DurationFormat.clock(0) == "0:00")
    #expect(DurationFormat.clock(9) == "0:09")
    #expect(DurationFormat.clock(65) == "1:05")
    #expect(DurationFormat.clock(600) == "10:00")
}

@Test func 时钟格式满一小时才显示小时位() {
    #expect(DurationFormat.clock(3599) == "59:59")
    #expect(DurationFormat.clock(3600) == "1:00:00")
    #expect(DurationFormat.clock(3665) == "1:01:05")
    #expect(DurationFormat.clock(36000) == "10:00:00")
}

@Test func 时钟格式负数按零处理() {
    #expect(DurationFormat.clock(-1) == "0:00")
}

@Test func 时钟格式秒与分永远补足两位() {
    // 大号计时用等宽数字，位数变化会让整行左右抖动。
    for s in [0, 5, 59, 60, 61, 599, 600, 3600, 3601] {
        let text = DurationFormat.clock(s)
        let parts = text.split(separator: ":")
        for part in parts.dropFirst() {
            #expect(part.count == 2, "\(text) 里的 \(part) 不是两位")
        }
    }
}

@Test func 口语时长() {
    #expect(DurationFormat.spoken(0) == "0 秒")
    #expect(DurationFormat.spoken(45) == "45 秒")
    #expect(DurationFormat.spoken(60) == "1 分")
    #expect(DurationFormat.spoken(61) == "1 分 1 秒")
    #expect(DurationFormat.spoken(1800) == "30 分")
    #expect(DurationFormat.spoken(3600) == "1 小时")
    #expect(DurationFormat.spoken(3661) == "1 小时 1 分")
    #expect(DurationFormat.spoken(7325) == "2 小时 2 分")
}

@Test func 口语时长满小时后不再报秒() {
    // 「1 小时 1 分 5 秒」太长，会把列表行挤换行。
    #expect(DurationFormat.spoken(3665) == "1 小时 1 分")
    #expect(DurationFormat.spoken(3605) == "1 小时")
}

@Test func 口语时长负数按零处理() {
    #expect(DurationFormat.spoken(-30) == "0 秒")
}
