import Foundation
import Observation

/// 设备本地偏好。**刻意不进 SwiftData**——
/// 这些是「这台设备怎么用」而不是「我做了多少功课」，
/// 同步过去只会让 iPad 上的静音设置莫名其妙跟着手机变。
///
/// 同样重要的是：它们进不了 CloudKit，就绝不可能挤占同步配额、
/// 也绝不可能因为同步冲突而丢功课数据。
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let sound = "settings.soundEnabled"
        static let haptic = "settings.hapticEnabled"
        static let dayStartHour = "settings.dayStartHour"
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `UserDefaults` 对没写过的键返回 false/0，而这两项应当默认开着，
        // 所以首次运行时显式落一次盘，之后一律以盘上的值为准。
        if defaults.object(forKey: Key.sound) == nil { defaults.set(true, forKey: Key.sound) }
        if defaults.object(forKey: Key.haptic) == nil { defaults.set(true, forKey: Key.haptic) }
        _soundEnabled = defaults.bool(forKey: Key.sound)
        _hapticEnabled = defaults.bool(forKey: Key.haptic)
        _dayStartHour = Self.clampHour(defaults.integer(forKey: Key.dayStartHour))
    }

    private var _soundEnabled: Bool
    private var _hapticEnabled: Bool
    private var _dayStartHour: Int

    var soundEnabled: Bool {
        get { _soundEnabled }
        set { _soundEnabled = newValue; defaults.set(newValue, forKey: Key.sound) }
    }

    var hapticEnabled: Bool {
        get { _hapticEnabled }
        set { _hapticEnabled = newValue; defaults.set(newValue, forKey: Key.haptic) }
    }

    /// 一日从几点算起。允许推后几小时，为的是夜里十一点做完晚课的人——
    /// 他心里那是「今天」的课。超过 6 点就荒唐了：会让上午的功课记到前一天。
    ///
    /// **界面在第 5 卷才开放，而且本卷「只存不用」**：此刻全仓库没有任何一处
    /// 从这里取值，`dayStartHour: 0` 的字面量仍散落在 DraftStore / DayLedger /
    /// 三个 ViewModel 里。（从前这段注释写的是「让所有调用点从同一处取值」，
    /// 与事实相反，已按实情改写——注释在说一件不成立的事，比没有注释更坏。）
    ///
    /// 第 5 卷把界面接上时，**必须把这批 `= 0` 的默认参数改成必填**，
    /// 否则只要有一个调用点忘了传，那一处就静默退回 0 点，而没有任何测试会红：
    /// 每条测试都自己显式传 `dayStartHour:`，谁也不会去问生产代码里它从哪儿来。
    var dayStartHour: Int {
        get { _dayStartHour }
        set {
            _dayStartHour = Self.clampHour(newValue)
            defaults.set(_dayStartHour, forKey: Key.dayStartHour)
        }
    }

    private static func clampHour(_ v: Int) -> Int { min(6, max(0, v)) }
}
