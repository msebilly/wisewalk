import Foundation

/// 引磬。§6.3.1：倒计时到零时响一声。
///
/// **合成而不是录音。** 这个项目是法布施、GPL-3.0 开源，一段录来的引磬会带着
/// 采样的版权来源问题——谁录的、许可是什么、能不能随 GPL 一起分发下去。
/// 合成的没有这些问题，也不占仓库体积。
///
/// 磬是**非谐**的：泛音不落在基频的整数倍上，这正是它听起来像金属而不像笛子的原因。
/// 下面几个比例取自小型手磬的大致轮廓；高次泛音衰减得更快，
/// 所以敲下去那一瞬间最亮，余韵里只剩低次泛音。
enum QingSound {
    static let sampleRate = 44_100
    static let durationSeconds = 3.0
    /// 基频。引磬音高偏高，落在人耳最敏感的区间，闭着眼睛也听得清。
    static let fundamental = 1_180.0
    /// 峰值幅度上界，0…1。留足余量——削顶的正弦听起来是爆音不是磬声。
    static let amplitude = 0.32

    /// （频率倍数，相对振幅，衰减时间常数秒）。**非整数倍是故意的，别「顺手改整齐」。**
    static let partials: [(ratio: Double, gain: Double, decay: Double)] = [
        (1.00, 1.00, 1.20),
        (2.03, 0.62, 0.70),
        (2.79, 0.38, 0.42),
        (4.11, 0.22, 0.25),
        (5.43, 0.12, 0.15),
    ]

    /// 各泛音振幅之和——`|Σ gain·sin(…)|` 的**理论上界**。
    /// 除掉它，`amplitude` 才真的是峰值的上界，五个泛音撞在一起也不会削顶。
    /// 实际峰值比这个小，所以听感会略轻于 `amplitude`——**安全方向**。
    static var normalizer: Double { partials.reduce(0) { $0 + $1.gain } }

    static func wavData() -> Data {
        let sampleCount = max(1, Int(Double(sampleRate) * durationSeconds))
        let scale = amplitude / normalizer
        var samples = [Double](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            let t = Double(i) / Double(sampleRate)
            var v = 0.0
            for p in partials {
                v += sin(2 * .pi * fundamental * p.ratio * t) * exp(-t / p.decay) * p.gain
            }
            samples[i] = v * scale
        }
        return WAVWriter.container(pcm: WAVWriter.pcm(from: samples), sampleRate: sampleRate)
    }
}
