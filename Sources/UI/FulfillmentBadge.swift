import SwiftUI

/// 圆满标记。
///
/// §7.2 硬约束 4：**必须「文字 + 颜色」双重编码**。
/// 只靠颜色的话，红绿色盲用户看到的是两个一模一样的圆环——
/// 而「今天到底圆满没有」是这个 App 唯一要回答的问题。
enum FulfillmentBadge {
    /// 状态的文字说法。`nil` 表示不显示徽标。
    static func text(for state: FulfillmentState) -> String? {
        switch state {
        case .fulfilled: "圆满"
        case .pending: nil          // 每天满屏「未完成」是在制造焦虑，与「随分随力」相违
        case .notRequired: "今日无课"
        }
    }

    /// 进度的文字说法。计数、计时、勾选三类各有各的说法。
    ///
    /// - Parameter rounds: 当日「做了几回」，只对计时类有意义。
    ///   用户定案：**打坐按「时间」和「坐数量」两个数**，一个数说不清
    ///   「坐了 45 分钟」是一口气坐的还是分三回凑的。
    ///   `0` 不显示——「0 坐」是噪声，圆环已经说明没做。
    ///   加在这个纯函数里而不是加在视图里，是因为 `TodayView` 有**两处**要说这句话：
    ///   可见副标题和 VoiceOver 的 `accessibilityLabel`。分开写迟早漏一处，
    ///   而漏掉的那处必定是听不见的那处。
    static func progressText(total: Int, goal: Int?, unit: String,
                             measureType: MeasureType, rounds: Int = 0) -> String {
        switch measureType {
        case .check:
            return total > 0 ? "已完成" : "未做"
        case .duration:
            let done = DurationFormat.clock(total)
            let 坐 = rounds > 0 ? " · \(rounds) 坐" : ""
            guard let goal, goal > 0 else { return done + 坐 }
            return "\(done) / \(DurationFormat.clock(goal))\(坐)"
        case .count:
            let suffix = unit.isEmpty ? "" : " \(unit)"
            guard let goal, goal > 0 else { return "\(total)\(suffix)" }
            return "\(total) / \(goal)\(suffix)"
        }
    }
}

struct FulfillmentLabel: View {
    let state: FulfillmentState
    @Environment(\.theme) private var theme

    var body: some View {
        if let text = FulfillmentBadge.text(for: state) {
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(state == .fulfilled ? theme.fulfilled : theme.tertiaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
            // 这里从前有一层同色 12% 的 Capsule 底。看着秀气，代价是
            // **文字站的底不再是审计时那个底**：`所有承载文字的色值都不低于AA标准`
            // 量的是色值对纯背景，而屏幕上真实合成出来的是——
            //   圆满 `#5C7652` on `#E7E8DD` = 4.075:1
            //   今日无课 `#6F6759` on `#E9E6DE` = 4.478:1
            // 双双跌破 4.5。
            //
            // §7.2 那句「不使用 opacity 派生层级」立案时写得很清楚：
            // 早期版本正是这么产生了 6 级低于 3:1 的文字，最糟的 Tab 标签只有 2.04:1。
            // 底板一去，两个色回到纯背景上（4.709 / 5.220），双双过线，
            // 也正合 §7.1「减法：去卡片描边、去图标底板」。
        }
    }
}
