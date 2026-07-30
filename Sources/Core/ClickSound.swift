import Foundation

/// 计数音的 PCM WAV 数据，**运行时合成，不打包音频资源**。
///
/// 为什么不用 `AudioServicesPlaySystemSound`：系统声不受 `AVAudioSession` 类目管辖，
/// 无法保证与用户正在放的念佛机混音——而 §6.2 把这一条列为硬要求，
/// 因为很多师兄一边放念佛机一边跟着计数，掐断它就是砸场子。
/// `AVAudioPlayer` 受类目管辖，但需要一段音频数据。
///
/// 为什么不往仓库里放个 wav：本项目是 GPL-3.0 公开发布，仓库里每个二进制
/// 都要能交代来源与授权。与其为一声「嗒」去处理授权，不如现算——
/// 一段 8 毫秒、带指数衰减的 880Hz 正弦，就是一声轻响。
enum ClickSound {
    static let sampleRate = 44_100
    static let durationSeconds = 0.008
    static let frequency = 880.0
    /// 峰值幅度，0…1。留足余量，削顶的正弦听起来是爆音不是轻响。
    static let amplitude = 0.35

    /// 16 位单声道 WAV。
    static func wavData() -> Data {
        let sampleCount = max(1, Int(Double(sampleRate) * durationSeconds))
        // 指数衰减：到结尾时已经接近静音，避免硬截断产生的爆响。
        let decay = durationSeconds / 3

        var pcm = Data(capacity: sampleCount * 2)
        for i in 0..<sampleCount {
            let t = Double(i) / Double(sampleRate)
            let envelope = exp(-t / decay)
            let value = sin(2 * .pi * frequency * t) * envelope * amplitude
            let clamped = max(-1.0, min(1.0, value))
            let sample = Int16(clamped * 32767)
            withUnsafeBytes(of: sample.littleEndian) { pcm.append(contentsOf: $0) }
        }

        var data = Data()
        func appendUInt32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func appendUInt16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }

        data.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(UInt32(36 + pcm.count))
        data.append(contentsOf: Array("WAVE".utf8))

        data.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(16)                                  // fmt 块长度
        appendUInt16(1)                                   // PCM
        appendUInt16(1)                                   // 单声道
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * 2))              // 字节率 = 采样率 × 声道 × 位宽/8
        appendUInt16(2)                                   // 块对齐
        appendUInt16(16)                                  // 位深

        data.append(contentsOf: Array("data".utf8))
        appendUInt32(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}
