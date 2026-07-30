import SwiftUI

/// 进度环。
///
/// **自身对辅助技术不可见**（`accessibilityHidden`）——环是纯装饰，
/// 圆满与否必须由调用方以文字说出来（见 `FulfillmentLabel`）。
/// 若让环也读一遍，VoiceOver 用户会听到两遍同样的话。
struct ProgressRing: View {
    let progress: Double
    let colorHex: String
    let trackHex: String
    let isFulfilled: Bool
    let iconName: String
    var diameter: CGFloat = 44
    /// design-spec §7.1 定的是 2.5–3px。粗环在小直径上会把中间那枚图标挤没。
    var lineWidth: CGFloat = 3

    /// 目标为 0 时 Double 除法会给出 inf/nan，直接喂给 `trim` 会画出乱七八糟的弧。
    static func clamp(_ v: Double) -> Double {
        guard v.isFinite else { return v.isNaN ? 0 : (v > 0 ? 1 : 0) }
        return min(1, max(0, v))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: trackHex).opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: Self.clamp(progress))
                .stroke(Color(hex: colorHex),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // 圆满时换成对勾：形状上就与未圆满不同，不依赖颜色。
            Image(systemName: isFulfilled ? "checkmark" : iconName)
                .font(.system(size: diameter * 0.34, weight: isFulfilled ? .bold : .regular))
                .foregroundStyle(Color(hex: colorHex))
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}
