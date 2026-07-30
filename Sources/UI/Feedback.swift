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
    /// 音频会话只配一次。**这个标志与 `player` 分开**：
    /// 若只用 `player == nil` 当哨兵，`AVAudioPlayer(data:)` 一旦持续失败，
    /// 底下 `tick` 那句补救会让**每敲一下**都重跑一次 `setCategory` + `setActive`——
    /// 而这是计数的热路径，用户一坐要敲一百零八下。
    private var sessionConfigured = false

    private init() {}

    /// 进入计数页时调一次，把震动马达和音频链路预热好。
    /// 不预热的话第一下会有可察觉的延迟，用户会以为没点上而补一下——那就多记了。
    func prepare() {
        haptics.prepare()
        configureSessionOnce()
        guard player == nil else { return }
        player = try? AVAudioPlayer(data: ClickSound.wavData())
        player?.prepareToPlay()
    }

    private func configureSessionOnce() {
        guard !sessionConfigured else { return }
        sessionConfigured = true
        // `.ambient` + `.mixWithOthers` 是硬要求：
        // 默认的 `.soloAmbient` 会把用户正在放的念佛机掐断。
        // `.ambient` 同时意味着遵守静音键——静音时就该静音，这是对的。
        try? AVAudioSession.sharedInstance()
            .setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// 点一下的反馈。两个开关互不影响。
    func tick(sound: Bool, haptic: Bool) {
        if haptic {
            haptics.impactOccurred()
        }
        if sound {
            if player == nil { prepare() }
            player?.currentTime = 0
            player?.play()
        }
    }
}
