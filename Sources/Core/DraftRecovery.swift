import Foundation

/// 崩溃之后，从草稿推断「该给用户补记多少」。纯函数，可穷举测试。
enum DraftRecovery {
    /// 建议补记的量。计数类为遍数，计时类为**秒**。
    ///
    /// 计时类**绝不能用「现在 − startedAt」**：App 可能崩在三天前，
    /// 那样会给用户记上 72 小时的打坐，而且是记进一个只增不减的账本。
    /// 能拿到的最好估计是最后一次心跳（`updatedAt`），
    /// 心跳间隔即误差上限（见 `TimerViewModel.heartbeatInterval`）。
    ///
    /// 一律不返回负数：用户改系统时间或时钟回拨都可能让 `updatedAt < startedAt`，
    /// 负值写进账本会被 `displayTotal` 的 clamp 掩盖成 0，不如在这里就拦住。
    static func suggestedAmount(
        source: SessionSource,
        amount: Int,
        startedAt: Date,
        updatedAt: Date
    ) -> Int {
        switch source {
        case .timer:
            return max(0, Int(updatedAt.timeIntervalSince(startedAt).rounded()))
        case .counter, .manual, .adjustment:
            return max(0, amount)
        }
    }

    /// 值得为它打扰用户吗。
    /// 点开计数器又立刻退出会留下一份空草稿，不该在下次启动时弹窗。
    static func isWorthRestoring(
        source: SessionSource,
        amount: Int,
        startedAt: Date,
        updatedAt: Date
    ) -> Bool {
        suggestedAmount(source: source, amount: amount,
                        startedAt: startedAt, updatedAt: updatedAt) > 0
    }

    /// 草稿的量法与定课**当前**的量法还对得上吗。
    ///
    /// 定课的量法是可以改的（`PracticeItemStore.update` 开放 `measureType`），而草稿
    /// 跨启动存活。改过之后旧草稿的 `amount` 与 `startedAt` 在新量法下每个字段都是错的，
    /// 拿去问用户「要恢复吗」，他确认的就是一笔错账——而账本只增不减，改回来得再写一笔负数。
    ///
    /// `DraftStore.begin` 挡的是「用户又进了计数器」那条路，这里挡的是「用户重启了 App」
    /// 那条。**两个入口都要挡**，缺一个就漏。
    static func matches(source: SessionSource, measureType: MeasureType) -> Bool {
        switch measureType {
        case .count: return source == .counter
        case .duration: return source == .timer
        // 打勾类就地记，根本不开计数/计时页，也就不会有草稿。
        // 真留下一份，只可能是量法改过来的，一律作废。
        case .check: return false
        }
    }
}
