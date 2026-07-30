import Foundation
import AVFoundation
import UIKit

/// 计数反馈。
///
/// §6.2：**音效与震动各自可独立开关**。这是**防漏记多记的功能性反馈，不是装饰**——
/// 念珠有手感，屏幕没有，用户需要一个「刚才那下算上了」的确认。
/// 有人在公共场合只要震动，有人戴着手套只要声音，所以两个开关得分开。
@MainActor
final class Feedback {
    static let shared = Feedback()

    private let haptics = UIImpactFeedbackGenerator(style: .light)
    private var player: AVAudioPlayer?

    private init() {
        // 媒体服务重启后，系统把类目打回默认，并让所有音频对象失效
        // （`AVAudioSessionTypes.h`：「re-initialize any audio objects used by your application」）。
        // 不重建的话，这一坐**剩下的每一下都会记进账本却不出声**——
        // 用户闭着眼睛数数，没听见就当刚才那下没点上，于是补一下，**多记**。
        // 而且不重启 App 就再也不会响。
        //
        // 中断、进后台、锁屏都不必管：实测播放器会隐式重新激活会话，自愈。
        // 媒体服务重启是**唯一**不自愈的那条，也是这台机器上永远照不出来的那条——
        // 模拟器根本没有 mediaserverd，这里全靠 Apple 写死的契约。
        _ = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.player = nil
                self?.prepare()
            }
        }
    }

    /// 进入计数页、以及每次回到前台时调用，把震动马达和音频链路预热好。
    /// 不预热的话第一下会有可察觉的延迟，用户会以为没点上而补一下——那就多记了。
    ///
    /// **每次都重配会话、每次都补建播放器，不留「配过了」的闩。**
    /// 闩记的是「我试过了」，不是「它现在是对的」：`setCategory` 在通话中会失败，
    /// 一个只进不出的闩会让类目**永远**停在 `.soloAmbient`，那就掐了用户的念佛机。
    /// 这里是冷路径（进页 / 回前台），一坐只走两三次，重配的代价可以忽略。
    func prepare() {
        haptics.prepare()
        // `.ambient` + `.mixWithOthers` 是硬要求：
        // 默认的 `.soloAmbient` 会把用户正在放的念佛机掐断。
        // `.ambient` 同时意味着遵守静音键——静音时就该静音，这是对的。
        try? AVAudioSession.sharedInstance()
            .setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        if player == nil {
            player = try? AVAudioPlayer(data: ClickSound.wavData())
        }
        player?.prepareToPlay()
    }

    /// 点一下的反馈。两个开关互不影响。
    ///
    /// **这里一个字的配置都不做。** 计数是热路径，用户一坐要敲一百零八下。
    /// 从前这儿有句 `if player == nil { prepare() }` 兜底，可播放器一旦建不起来，
    /// 它就变成每敲一下重跑一次 `setCategory` + `setActive`。
    /// 预热归 `prepare()` 管，它在进页和回前台各调一次，够了。
    func tick(sound: Bool, haptic: Bool) {
        if haptic {
            haptics.impactOccurred()
            // 预热状态是被事件消费掉的（`UIFeedbackGenerator.h`：
            // 「safe to call more than once **before** the generator receives an event」）。
            // 不补这一句，第 2 下到第 108 下全是从冷态起振。
            haptics.prepare()
        }
        if sound {
            player?.currentTime = 0
            player?.play()
        }
    }
}
