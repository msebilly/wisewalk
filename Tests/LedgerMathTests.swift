import Testing
import Foundation
@testable import WiseWalk

@Test func 空账本求和为零() {
    // 必须写明 [Int]()：rawTotal 有 [Int] 与 [PracticeSession] 两个重载，
    // 空数组字面量会让类型推断无法决断。
    #expect(LedgerMath.rawTotal([Int]()) == 0)
    #expect(LedgerMath.displayTotal([Int]()) == 0)
}

@Test func 多笔流水求和() {
    #expect(LedgerMath.rawTotal([108, 500, 21]) == 629)
}

@Test func 负数修正抵扣() {
    #expect(LedgerMath.rawTotal([500, -200]) == 300)
}

@Test func 撤销过头时账本可为负而显示归零() {
    #expect(LedgerMath.rawTotal([100, -300]) == -200)
    #expect(LedgerMath.displayTotal([100, -300]) == 0, "账本保留原值，只有显示层归零")
}

@Test func 设了目标时达标才算圆满() {
    #expect(LedgerMath.isFulfilled(total: 999, goal: 1000) == false)
    #expect(LedgerMath.isFulfilled(total: 1000, goal: 1000) == true)
    #expect(LedgerMath.isFulfilled(total: 3000, goal: 1000) == true)
}

@Test func 未设目标时做了就算圆满() {
    // 九款竞品无一预设目标数字，「随分随力」是这款 App 的立场。
    #expect(LedgerMath.isFulfilled(total: 0, goal: nil) == false)
    #expect(LedgerMath.isFulfilled(total: 1, goal: nil) == true)
    #expect(LedgerMath.isFulfilled(total: 108, goal: nil) == true)
}

@Test func 目标为零等同未设目标() {
    #expect(LedgerMath.isFulfilled(total: 0, goal: 0) == false)
    #expect(LedgerMath.isFulfilled(total: 1, goal: 0) == true)
}

@Test func 撤销归零后不算圆满() {
    let total = LedgerMath.displayTotal([1000, -1000])
    #expect(total == 0)
    #expect(LedgerMath.isFulfilled(total: total, goal: 1000) == false)
    #expect(LedgerMath.isFulfilled(total: total, goal: nil) == false)
}

@Test func 大数值不溢出() {
    // 闭关的师兄一天几万声，五年下来累计上千万，必须扛得住。
    let big = Array(repeating: 100_000, count: 10_000)
    #expect(LedgerMath.rawTotal(big) == 1_000_000_000)
}
