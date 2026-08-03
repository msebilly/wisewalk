import Testing
import SwiftUI
import SwiftData
import Foundation
@testable import WiseWalk

// MARK: - 这个文件测到了什么，没测到什么
//
// **测到的只有两样**：`CounterView.bigNumberText` 这个纯函数，以及视图能否实例化。
// 计数器的行为（草稿承接、结束落账、一声没念不留空账）全部由
// `CounterViewModelTests` 覆盖，那里一律固定时区、固定时刻。
//
// **这里曾经有三条同名不同实的重复**（`进页面会承接未提交的草稿`、
// `页面退出时提交一笔`、`一声没数就退出不留空记录`），它们用 `DayKey.today()`，
// 也就是 `Date()` + `TimeZone.current`。2026-07-31 实测这个走样：
// 把 `CounterViewModel.start` 里的 `self.timeZone = timeZone` 改成 `.current`，
// `CounterViewModelTests` **红 6 条 10 个 issue**，这三条**一条都不红**——
// 断言和实现用的是同一把歪尺子。它们比被重复的那三条还弱
// （按天过滤的 `sessions(on:).isEmpty` vs 全库的 `库里一条流水都没有`），
// 所以删掉，不是改稳。`AppEnvironment` 的装配由
// `AppEnvironmentTests.装配后三个仓储共用同一个上下文` 管，也不归这里。
//
// **视图接线没有任何覆盖**：哪个字段传给哪个参数、§6.2「结束与返回区域不参与计数」
// 靠 `safeAreaInset` 结构性分层保证——改错了都不会红。
// 实测：大号数字 `vm.dayTotal` → `vm.count`，全绿。
// 目前唯一的对策是结构性的（`subtitle` 收进一个计算属性，
// 可见文字与 VoiceOver 共用同一处），**这不是覆盖，别当成覆盖**。

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

// MARK: - 拨念珠念的那些，怎么记进来（2026-08-03）

@Test func 批量增加的按钮上写的数就是要加的数() {
    // 屏幕说的和做的必须是同一件事。这是唯一一处告诉用户「这一下要加多少」的地方，
    // 按下去之后就进账本了，没有第二次确认。
    #expect(BatchSheet.confirmText(500) == "加 500")
    #expect(BatchSheet.confirmText(324) == "加 324")
}

@Test func 数写不出来时不许按加() {
    // `numericText` 把空框映射成 0，而 `setBatchStep` 会 `max(1,)` 把 0 抬成 1。
    // 不禁用的话，按钮上写着「加 0」、实际加 1——**方向是「多」**。
    #expect(BatchSheet.canConfirm(0) == false, "空框还能按，按下去会凭空多一声")
    #expect(BatchSheet.canConfirm(-3) == false)
    #expect(BatchSheet.canConfirm(1) == true)
    #expect(BatchSheet.canConfirm(324) == true)
}

@Test func 计数区的提示不许承诺读屏用户做不到的手势() {
    // 「长按批量增加」这句话是念给 VoiceOver 用户听的，
    // 而读屏模式下长按被系统接管，他**做不到**。
    // 说了做不到，比不说更坏（§6.3.1「半真的承诺比不承诺更坏」是同一条）。
    #expect(!CounterView.countingHint.contains("长按"),
            "提示里还在教用户做一个他做不出来的手势")
    #expect(CounterView.countingHint.contains("轻点"), "轻点加一这件事还是得说")
}
