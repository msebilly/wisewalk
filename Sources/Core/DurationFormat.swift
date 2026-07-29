import Foundation

/// 秒 → 人看的文本。纯函数。
///
/// **刻意不用 `DateComponentsFormatter`**：它会按当前语言产出「1小时5分」这类
/// 长度不定的文本，在等宽数字的大号计时上会左右抖动——
/// 与 §6.2「数字用 `.monospacedDigit()`，否则整行左右抖动」是同一个毛病。
enum DurationFormat {
    /// 计时器上的走时：`"1:05"` / `"1:01:05"`。分与秒永远补足两位。
    static func clock(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// 列表与确认文案里的时长：`"30 分"` / `"1 小时 1 分"` / `"45 秒"`。
    /// 满一小时后不再报秒——「1 小时 1 分 5 秒」会把列表行挤到换行。
    static func spoken(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return m > 0 ? "\(h) 小时 \(m) 分" : "\(h) 小时"
        }
        if m > 0 {
            return s > 0 ? "\(m) 分 \(s) 秒" : "\(m) 分"
        }
        return "\(s) 秒"
    }
}
