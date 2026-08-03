import Testing
import SwiftUI
import SwiftData
import Foundation
@testable import WiseWalk

// MARK: - 这个文件测到了什么，没测到什么
//
// **只测视图能否实例化。** 计时器的行为（时间戳差值、结束落账、不足一秒不留空账、
// 跨零点、四小时闸门）全部由 `TimerViewModelTests` 覆盖，那里一律固定时区、固定时刻；
// 走时文案由 `DurationFormatTests` 覆盖。
//
// **不要把 ViewModel 测试搬进来。** 搬进来的版本必然更弱（`DayKey.today()` 与实现
// 共用 `.current` 这把歪尺子、断言按天过滤而非全库），而文件名会替它撒谎——
// 读的人以为这一页被覆盖了。Task 15 因此删过三条。
//
// **视图接线没有任何覆盖**：哪个字段传给哪个参数、每秒 tick 是否真的调 `refresh`，
// 改错了都不会红。对策是结构性的（要说两遍的话收进一个计算属性），**不是覆盖**。

@MainActor
private func makeTimerEnv() throws -> (AppEnvironment, PracticeItem) {
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let item = try env.items.create(name: "打坐", measureType: .duration, unit: "",
                                    dailyGoal: 1800, iconName: "figure.mind.and.body",
                                    colorHex: Palette.Light.accent)
    return (env, item)
}

@MainActor
@Test func 计时器页能实例化() throws {
    let (env, item) = try makeTimerEnv()
    _ = TimerView(vm: TimerViewModel(item: item, drafts: env.drafts, ledger: env.ledger),
                  settings: env.settings, onFinish: {})
}

@MainActor
@Test func 走时和今日两个数得分得出哪个是哪个() throws {
    // ⛔ 屏幕上摞着两个数，格式一模一样，一个字的说明都没有：
    //
    //     10:00        ← 本轮走时
    //     40:00        ← 今日已记（含本轮）
    //
    // 当天头一坐时它们**恒等**（今日 = 0 + 本轮），于是同一个数印了两遍；
    // 第二坐起才分家，而那时用户没有任何依据判断哪个是哪个。
    //
    // 计数器页把这件事做对了：大号是今日，本轮另配「本次 N」的**标签**。
    // 计时页把两个数对调了，还把标签丢了。
    //
    // 读屏软件更惨：这一页零无障碍标注，两个 `Text` 都念成「四十比零零」。
    let (env, item) = try makeTimerEnv()
    let vm = TimerViewModel(item: item, drafts: env.drafts, ledger: env.ledger)

    // 当天头一坐、还没有目标以外的任何背景：小号必须自报家门。
    let 头一坐 = TimerView.subtitleText(dayTotal: 0, goal: nil, unit: "",
                                       measureType: .duration, rounds: 0)
    #expect(头一坐 == "今日 0:00", "小号是今日累计，得说出「今日」——不然它和大号长得一模一样")

    // 有目标时那道斜杠自己会说话，但「今日」仍不能省：斜杠说的是「几分之几」，
    // 不是「谁的几分之几」。
    #expect(TimerView.subtitleText(dayTotal: 300, goal: 1800, unit: "",
                                   measureType: .duration, rounds: 1) == "今日 5:00 / 30:00 · 1 坐")

    // 「· N 坐」这个后缀 `progressText` 早就会拼了，这一页不许自己再拼一遍——
    // 拼两遍就会有两种说法（纪律 ㉒）。这条钉住两处说的是同一句。
    #expect(TimerView.subtitleText(dayTotal: 2400, goal: nil, unit: "",
                                   measureType: .duration, rounds: 2)
            == "今日 " + FulfillmentBadge.progressText(total: 2400, goal: nil, unit: "",
                                                      measureType: .duration, rounds: 2))

    // 读屏软件听到的必须是两个**带名字**的数，而不是两个赤裸的时刻。
    let 念出来 = TimerView.spokenValue(clock: "10:00", subtitle: 头一坐)
    #expect(念出来.contains("本次"), "大号是本轮，读屏得说出来")
    #expect(念出来.contains("今日"), "小号是今日，读屏也得说出来")
    _ = vm
}
