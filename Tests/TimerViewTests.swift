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
