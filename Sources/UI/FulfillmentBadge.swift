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
    static func progressText(total: Int, goal: Int?, unit: String,
                             measureType: MeasureType) -> String {
        switch measureType {
        case .check:
            return total > 0 ? "已完成" : "未做"
        case .duration:
            let done = DurationFormat.clock(total)
            guard let goal, goal > 0 else { return done }
            return "\(done) / \(DurationFormat.clock(goal))"
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
                .background(
                    Capsule().fill(
                        (state == .fulfilled ? theme.fulfilled : theme.tertiaryText).opacity(0.12)
                    )
                )
        }
    }
}
