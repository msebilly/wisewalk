import Foundation

/// 账本算术。纯函数，不碰 SwiftData，因此可以被穷举测试。
enum LedgerMath {
    /// 账本原值求和。**撤销过多时可以为负**——这是账本的真实状态，不要在这里掩盖。
    static func rawTotal(_ amounts: [Int]) -> Int {
        amounts.reduce(0, +)
    }

    /// 显示用总数。负数 clamp 到 0，**账本本身纹丝不动**。
    static func displayTotal(_ amounts: [Int]) -> Int {
        max(0, rawTotal(amounts))
    }

    /// 是否圆满。
    /// - Parameter goal: nil 或 0 表示未设目标，此时「做了就算圆满」。
    static func isFulfilled(total: Int, goal: Int?) -> Bool {
        guard let goal, goal > 0 else { return total > 0 }
        return total >= goal
    }
}

extension LedgerMath {
    static func rawTotal(_ sessions: [PracticeSession]) -> Int {
        rawTotal(sessions.map(\.amount))
    }

    static func displayTotal(_ sessions: [PracticeSession]) -> Int {
        displayTotal(sessions.map(\.amount))
    }
}
