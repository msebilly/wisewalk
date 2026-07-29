import Testing
import Foundation
@testable import WiseWalk

private let 起点 = Date(timeIntervalSince1970: 1_785_000_000)

@Test func 计数类按草稿里记下的量恢复() {
    #expect(DraftRecovery.suggestedAmount(source: .counter, amount: 108,
                                          startedAt: 起点, updatedAt: 起点.addingTimeInterval(600)) == 108)
}

@Test func 计时类按最后一次心跳推算而不是按现在() {
    // 这是本文件存在的全部理由。
    // App 可能崩在三天前，用「现在 − startedAt」会给用户记上 72 小时的打坐。
    let 心跳 = 起点.addingTimeInterval(1800)   // 半小时
    #expect(DraftRecovery.suggestedAmount(source: .timer, amount: 0,
                                          startedAt: 起点, updatedAt: 心跳) == 1800)
}

@Test func 计时类忽略草稿里的量() {
    // 计时草稿的 amount 恒为 0，但即便被写脏了也不该影响推算。
    #expect(DraftRecovery.suggestedAmount(source: .timer, amount: 999_999,
                                          startedAt: 起点, updatedAt: 起点.addingTimeInterval(60)) == 60)
}

@Test func 心跳早于起始时按零处理不给负数() {
    // 用户改系统时间、或时钟回拨，都可能让 updatedAt < startedAt。
    // 负的时长写进账本会被 clamp 掩盖成 0，不如在这里就拦住。
    #expect(DraftRecovery.suggestedAmount(source: .timer, amount: 0,
                                          startedAt: 起点, updatedAt: 起点.addingTimeInterval(-500)) == 0)
    #expect(DraftRecovery.suggestedAmount(source: .counter, amount: -7,
                                          startedAt: 起点, updatedAt: 起点) == 0)
}

@Test func 不足半秒的计时四舍五入到零() {
    #expect(DraftRecovery.suggestedAmount(source: .timer, amount: 0,
                                          startedAt: 起点, updatedAt: 起点.addingTimeInterval(0.4)) == 0)
    #expect(DraftRecovery.suggestedAmount(source: .timer, amount: 0,
                                          startedAt: 起点, updatedAt: 起点.addingTimeInterval(0.6)) == 1)
}

@Test func 空草稿不值得打扰用户() {
    // 点开计数器又立刻退出，不该在下次启动时弹窗。
    #expect(!DraftRecovery.isWorthRestoring(source: .counter, amount: 0,
                                            startedAt: 起点, updatedAt: 起点))
    #expect(!DraftRecovery.isWorthRestoring(source: .timer, amount: 0,
                                            startedAt: 起点, updatedAt: 起点))
    #expect(DraftRecovery.isWorthRestoring(source: .counter, amount: 1,
                                           startedAt: 起点, updatedAt: 起点))
    #expect(DraftRecovery.isWorthRestoring(source: .timer, amount: 0,
                                           startedAt: 起点, updatedAt: 起点.addingTimeInterval(1)))
}

@Test func 手动来源退化成按量恢复() {
    // 草稿理论上只会是 counter / timer，但枚举以后可能加成员。
    // 与 ScheduleRule 同一条原则：无法识别时退化成不丢数据的那一侧。
    #expect(DraftRecovery.suggestedAmount(source: .manual, amount: 42,
                                          startedAt: 起点, updatedAt: 起点.addingTimeInterval(9999)) == 42)
    #expect(DraftRecovery.suggestedAmount(source: .adjustment, amount: 42,
                                          startedAt: 起点, updatedAt: 起点) == 42)
}

@Test func 量法与草稿对得上才认() {
    #expect(DraftRecovery.matches(source: .counter, measureType: .count))
    #expect(DraftRecovery.matches(source: .timer, measureType: .duration))
}

@Test func 量法改过的草稿一律作废() {
    // 定课的量法可以改，草稿跨启动存活。改过之后旧草稿的 amount 与 startedAt
    // 在新量法下每个字段都是错的——一份 108 遍的计数草稿被当成计时的来恢复，
    // 或者反过来把半小时打坐记成 108 秒，都会写进只增不减的账本。
    #expect(!DraftRecovery.matches(source: .timer, measureType: .count))
    #expect(!DraftRecovery.matches(source: .counter, measureType: .duration))
    // 打勾类根本不开草稿；真留下一份，只可能是量法改过来的。
    #expect(!DraftRecovery.matches(source: .counter, measureType: .check))
    #expect(!DraftRecovery.matches(source: .timer, measureType: .check))
    // 补记与修正走的是另一条路，从不产生草稿，同样不该被恢复流程认领。
    #expect(!DraftRecovery.matches(source: .manual, measureType: .count))
    #expect(!DraftRecovery.matches(source: .adjustment, measureType: .duration))
}
