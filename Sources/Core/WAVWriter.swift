import Foundation

/// 16 位单声道 WAV 容器。
///
/// **两个音源共用一份头部写法**（`ClickSound` 的点击声、`QingSound` 的引磬）。
/// 各写各的话，两份头部里迟早有一份填错某个数值字段——而错了的那份**不会崩**，
/// 只会让声音闷掉或变调，谁也不会立刻发现。
/// （Task 12 实测：`AVAudioPlayer(data:)` 对 12 种头部变异一次都没抛过。）
enum WAVWriter {
    static let bitsPerSample = 16
    static let channels = 1

    /// 把打包好的 PCM 套上 RIFF/WAVE 头。
    static func container(pcm: Data, sampleRate: Int) -> Data {
        var data = Data(capacity: 44 + pcm.count)
        func appendUInt32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func appendUInt16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }

        let blockAlign = channels * bitsPerSample / 8

        data.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(UInt32(36 + pcm.count))
        data.append(contentsOf: Array("WAVE".utf8))

        data.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(16)                                   // fmt 块长度
        appendUInt16(1)                                    // PCM
        appendUInt16(UInt16(channels))
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * blockAlign))      // 字节率
        appendUInt16(UInt16(blockAlign))
        appendUInt16(UInt16(bitsPerSample))

        data.append(contentsOf: Array("data".utf8))
        appendUInt32(UInt32(pcm.count))
        data.append(pcm)
        return data
    }

    /// 把 −1…1 的浮点采样打包成小端 16 位 PCM，顺带削顶保护。
    static func pcm(from samples: [Double]) -> Data {
        var out = Data(capacity: samples.count * 2)
        for v in samples {
            let clamped = max(-1.0, min(1.0, v))
            let sample = Int16(clamped * 32767)
            withUnsafeBytes(of: sample.littleEndian) { out.append(contentsOf: $0) }
        }
        return out
    }
}
