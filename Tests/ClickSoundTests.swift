import Testing
import Foundation
import AVFoundation
@testable import WiseWalk

@Test func WAV头部是合法的RIFF() {
    let d = ClickSound.wavData()
    #expect(Array(d.prefix(4)) == Array("RIFF".utf8))
    #expect(Array(d[8..<12]) == Array("WAVE".utf8))
    #expect(Array(d[12..<16]) == Array("fmt ".utf8))
    #expect(Array(d[36..<40]) == Array("data".utf8))
}

@Test func WAV长度与采样数吻合() {
    let d = ClickSound.wavData()
    let samples = Int(Double(ClickSound.sampleRate) * ClickSound.durationSeconds)
    #expect(d.count == 44 + samples * 2, "44 字节头 + 16 位单声道 PCM，实际 \(d.count)")
}

@Test func WAV声明的数据长度与实际一致() {
    // 这个字段写错，播放器要么截断要么读越界，而且不会报错——只是没声音。
    let d = ClickSound.wavData()
    let declared = d[40..<44].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
    #expect(Int(declared) == d.count - 44)
    let riffSize = d[4..<8].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
    #expect(Int(riffSize) == d.count - 8)
}

/// 把 WAV 的 PCM 段解成 Int16 数组。
private func 采样(_ d: Data) -> [Int16] {
    stride(from: 44, to: d.count - 1, by: 2).map {
        Int16(bitPattern: UInt16(d[$0]) | (UInt16(d[$0 + 1]) << 8))
    }
}

@Test func 采样不削顶() {
    // 削顶的正弦听起来是「咔」的一声爆音，不是轻响。
    let peak = 采样(ClickSound.wavData()).map { Int32($0).magnitude }.max() ?? 0
    #expect(peak < 32767, "峰值 \(peak) 已经削顶")
    #expect(peak > 1000, "峰值 \(peak) 太轻，等于没声音")
}

@Test func 结尾的振幅必须比开头小一大截() {
    // 不衰减的话会在结尾突然截断，产生一声爆响。
    //
    // ⚠️ **别拿末样本一个数去断言。** 880Hz × 8ms = 7.04 个周期，
    // 末样本恰好落在正弦的过零点附近：把整个包络删掉，它也才 294,
    // 任何「末样本 < 两千」之类的阈值都照样绿。实算过。
    // 要照出「有没有衰减」，得比**两段的峰值**——
    // 有衰减时后四分之一比前四分之一小 8.6 倍，没衰减时是 1.00 倍。
    let s = 采样(ClickSound.wavData())
    let q = s.count / 4
    let 头 = s[0..<q].map { Int32($0).magnitude }.max() ?? 0
    let 尾 = s[(s.count - q)...].map { Int32($0).magnitude }.max() ?? 0
    #expect(头 > 尾 * 4, "头 \(头) / 尾 \(尾)：衰减不明显，结尾会有截断爆音")
}

@Test func 合成结果能被AVAudioPlayer接受() throws {
    // 头部写错只会导致「没声音」，不会报错——必须真的喂给播放器验一遍。
    let player = try AVAudioPlayer(data: ClickSound.wavData())
    #expect(player.prepareToPlay())
    #expect(abs(player.duration - ClickSound.durationSeconds) < 0.003,
            "时长 \(player.duration)，期望约 \(ClickSound.durationSeconds)")
}

@Test func 反复合成结果完全一致() {
    #expect(ClickSound.wavData() == ClickSound.wavData())
}
