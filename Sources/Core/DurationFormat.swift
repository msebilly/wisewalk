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

/// 时长的**输入**与显示互转：计时类的 `amount` 存的是秒，但没人愿意填 1800。
///
/// 与 `DurationFormat` 分开，是因为方向相反——那个是「秒 → 给人看的字」，
/// 这个是「人转出来的时分 → 秒」，且必须可逆（`split` 与 `seconds` 来回不丢数）。
///
/// **住在 Core 而不是补记页里**：Task 16 的计时页在读数超过四小时时也要弹时长转盘
/// 问用户实际坐了多久，它排在补记页前面。当初把这个类型写在 `ManualEntryView.swift`
/// 里，等于让 Task 16 引用一个还不存在的类型。
enum DurationField {
    static func split(seconds: Int) -> (hours: Int, minutes: Int) {
        guard seconds > 0 else { return (0, 0) }
        return (seconds / 3600, (seconds % 3600) / 60)
    }

    static func seconds(hours: Int, minutes: Int) -> Int {
        max(0, hours) * 3600 + max(0, minutes) * 60
    }
}
