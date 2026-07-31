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
        static let qing = "settings.qingEnabled"
        static let qingLockScreenNoticed = "settings.qingLockScreenNoticed"
        static let dayStartHour = "settings.dayStartHour"
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `UserDefaults` 对没写过的键返回 false/0，而这两项应当默认开着，
        // 所以首次运行时显式落一次盘，之后一律以盘上的值为准。
        if defaults.object(forKey: Key.sound) == nil { defaults.set(true, forKey: Key.sound) }
        if defaults.object(forKey: Key.haptic) == nil { defaults.set(true, forKey: Key.haptic) }
        if defaults.object(forKey: Key.qing) == nil { defaults.set(true, forKey: Key.qing) }
        _soundEnabled = defaults.bool(forKey: Key.sound)
        _hapticEnabled = defaults.bool(forKey: Key.haptic)
        _qingEnabled = defaults.bool(forKey: Key.qing)
        _qingLockScreenNoticed = defaults.bool(forKey: Key.qingLockScreenNoticed)
        _dayStartHour = Self.clampHour(defaults.integer(forKey: Key.dayStartHour))
    }

    private var _soundEnabled: Bool
    private var _hapticEnabled: Bool
    private var _qingEnabled: Bool
    private var _qingLockScreenNoticed: Bool
    private var _dayStartHour: Int

    var soundEnabled: Bool {
        get { _soundEnabled }
        set { _soundEnabled = newValue; defaults.set(newValue, forKey: Key.sound) }
    }

    var hapticEnabled: Bool {
        get { _hapticEnabled }
        set { _hapticEnabled = newValue; defaults.set(newValue, forKey: Key.haptic) }
    }

    /// 倒计时到零时响引磬。§6.3.1。
    ///
    /// **独立于 `soundEnabled`**：念佛不想每声都响、但下坐要知道，是很合理的组合。
    ///
    /// ⚠️ 前台与后台走的是**两套声音通道**，音量归谁管都不一样，设置页必须写明：
    /// 前台是 `AVAudioPlayer` + `.ambient`（**媒体音量**），
    /// 后台是本地通知（**铃声音量**）。同一声引磬，锁屏时可能明显更响。
    /// 这个不一致消不掉——通知声音归系统管，App 的 audio session 类目管不着它。
    ///
    /// 两条路都跟随物理静音键。**不做「静音也响」**：前台技术上做得到
    /// （`.playback` + `mixWithOthers`），**后台做不到**——本地通知越过静音键要
    /// Critical Alerts 权限，那是给医疗与安防类 App 的，我们申请不下来。
    /// 那会得到一个只在前台成立的承诺，**半真的承诺比不承诺更坏**。
    var qingEnabled: Bool {
        get { _qingEnabled }
        set { _qingEnabled = newValue; defaults.set(newValue, forKey: Key.qing) }
    }

    /// 「没给通知权限，锁屏时不会响」这句话是否已经对用户说过。
    ///
    /// **默认 false，说过一次就落盘。** 这一句必须说（不吭声的降级会让他以为
    /// 倒计时在替他守着），但只该说一次：拒绝之后每坐一次弹一遍，用户会学会
    /// 闭着眼点掉，那时连真正要紧的话也一并被点掉了。
    ///
    /// ⚠️ 这是**唯一**一个不该出现在设置页上的键——它不是偏好，是「说过没有」的备忘。
    var qingLockScreenNoticed: Bool {
        get { _qingLockScreenNoticed }
        set {
            _qingLockScreenNoticed = newValue
            defaults.set(newValue, forKey: Key.qingLockScreenNoticed)
        }
    }

    /// 一日从几点算起。允许推后几小时，为的是夜里十一点做完晚课的人——
    /// 他心里那是「今天」的课。超过 6 点就荒唐了：会让上午的功课记到前一天。
    ///
    /// **界面在第 5 卷才开放。** Task 13 这个时点上它还有零个读者；
    /// Task 14 起各视图会把 `settings.dayStartHour` 传给 store 和 ViewModel，
    /// 但全卷没有一个 `Toggle` 能改它，值恒为 0。
    ///（原先这里写的是「本卷让所有调用点从同一处取值」，当时与事实相反，已改写。）
    ///
    /// **接线时当心**：`DraftStore` / `DayLedger` 和三个 ViewModel 的
    /// `dayStartHour` 都带着 `= 0` 的默认值。漏传一处，那一处就**静默退回 0 点，
    /// 而没有任何测试会红**——每条测试都自己显式传 `dayStartHour:`，
    /// 谁也不会去问生产代码里这个参数是从哪儿来的。
    /// 第 5 卷把界面接上、值不再恒为 0 之后，这批默认值应当改成必填。
    var dayStartHour: Int {
        get { _dayStartHour }
        set {
            _dayStartHour = Self.clampHour(newValue)
            defaults.set(_dayStartHour, forKey: Key.dayStartHour)
        }
    }

    private static func clampHour(_ v: Int) -> Int { min(6, max(0, v)) }
}
