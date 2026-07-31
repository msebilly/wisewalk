import Testing
import SwiftUI
import SwiftData
import Foundation
@testable import WiseWalk

@MainActor
private func makeCounterEnv() throws -> (AppEnvironment, PracticeItem) {
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let item = try env.items.create(name: "念佛", measureType: .count, unit: "声",
                                    dailyGoal: 1080, iconName: "circle.grid.3x3",
                                    colorHex: Palette.Light.fulfilled)
    return (env, item)
}

@MainActor
@Test func 计数器页能实例化() throws {
    let (env, item) = try makeCounterEnv()
    _ = CounterView(vm: CounterViewModel(item: item, drafts: env.drafts, ledger: env.ledger),
                    settings: env.settings, onFinish: {})
}

@MainActor
@Test func 批量弹层能实例化() {
    _ = BatchSheet(step: .constant(108), onConfirm: {})
}

@MainActor
@Test func 批量步长档位含一串念珠() {
    // 108 是全清单里唯一有客观依据的数字：一串念珠即 108 颗。
    #expect(BatchSheet.stepChoices.contains(108))
    #expect(BatchSheet.stepChoices.contains(1080))
    #expect(BatchSheet.stepChoices.allSatisfy { $0 > 0 })
    #expect(BatchSheet.stepChoices == BatchSheet.stepChoices.sorted())
}

@MainActor
@Test func 大号数字用等宽避免抖动() throws {
    // §6.2：1→2 时若不等宽，整行会左右抖动，数得越快抖得越凶。
    // 字体是视图属性，测不出来；这里锁住它依赖的格式函数不引入分组符号。
    #expect(CounterView.bigNumberText(1000) == "1000", "别出现千分位逗号")
    #expect(CounterView.bigNumberText(0) == "0")
    #expect(CounterView.bigNumberText(108) == "108")
}

@MainActor
@Test func 进页面会承接未提交的草稿() throws {
    // 崩溃后重进，之前数的不能凭空消失。
    let (env, item) = try makeCounterEnv()
    let a = CounterViewModel(item: item, drafts: env.drafts, ledger: env.ledger)
    try a.start()
    try a.tap(); try a.tap(); try a.tap()
    #expect(a.count == 3)

    let b = CounterViewModel(item: item, drafts: env.drafts, ledger: env.ledger)
    try b.start()
    #expect(b.count == 3, "重进页面把之前数的 3 声丢了")
}

@MainActor
@Test func 页面退出时提交一笔() throws {
    let (env, item) = try makeCounterEnv()
    let vm = CounterViewModel(item: item, drafts: env.drafts, ledger: env.ledger)
    try vm.start()
    for _ in 0..<108 { try vm.tap() }
    #expect(try env.ledger.total(on: DayKey.today(), itemID: item.id) == 0,
            "§6.2：结束时才写入，中途不许落账")

    let s = try vm.finish()
    #expect(s?.amount == 108)
    #expect(s?.source == .counter)
    #expect(try env.ledger.total(on: DayKey.today(), itemID: item.id) == 108)
    #expect(try env.drafts.pendingDrafts().isEmpty, "提交后草稿必须清掉")
}

@MainActor
@Test func 一声没数就退出不留空记录() throws {
    let (env, item) = try makeCounterEnv()
    let vm = CounterViewModel(item: item, drafts: env.drafts, ledger: env.ledger)
    try vm.start()
    #expect(try vm.finish() == nil)
    #expect(try env.ledger.sessions(on: DayKey.today(), itemID: item.id).isEmpty)
    #expect(try env.drafts.pendingDrafts().isEmpty)
}
