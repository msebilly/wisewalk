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

    // fmt 块的**数值**字段。`byteRate` 与 `blockAlign` 写错时，CoreAudio 照样
    // 播得好好的（实测 macOS 与 iOS 26.5 上 duration 分毫不变），所以下面两句
    // 挡不住任何听得见的毛病——它们守的是「这段字节拿出去也是合法 WAV」。
    // 没有它们，这条测试就担不起自己的名字：光验四个块标记不叫「合法」。
    func u16(_ o: Int) -> Int { Int(d[o..<(o + 2)].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self).littleEndian }) }
    func u32(_ o: Int) -> Int { Int(d[o..<(o + 4)].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }) }
    #expect(u32(16) == 16, "fmt 块长度")
    #expect(u16(20) == 1, "PCM")
    #expect(u16(22) == 1, "单声道")
    #expect(u32(24) == ClickSound.sampleRate)
    #expect(u32(28) == ClickSound.sampleRate * 2, "字节率 = 采样率 × 声道 × 位宽/8")
    #expect(u16(32) == 2, "块对齐")
    #expect(u16(34) == 16, "位深")
}

@Test func WAV长度与采样数吻合() {
    let d = ClickSound.wavData()
    let samples = Int(Double(ClickSound.sampleRate) * ClickSound.durationSeconds)
    #expect(d.count == 44 + samples * 2, "44 字节头 + 16 位单声道 PCM，实际 \(d.count)")
}

@Test func WAV声明的数据长度与实际一致() {
    // 这两个字段全靠这条测试守着，别的六条谁都碰不到它们。
    //
    // 别信「写错了播放器会截断或读越界」那套说法——实测把 data 长度写成 `pcm.count - 2`，
    // `AVAudioPlayer` 既没截断也没报错，`prepareToPlay()` 照样返回 true，
    // 只是时长少了一个采样（0.0079592 对 0.0079819）。
    // 也就是说**下游没有任何人会替我们发现这个错**，只能在这里当场比对。
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
    //
    // 上界看着松，其实是**恰好**的：`clamped` 被夹在 [−1, 1]，`|sample|` 数学上
    // 就不可能超过 32767，所以「峰值 < 32767」的真实含义是**那句 clamp 从没触发过**——
    // 而 clamp 触发正是削顶的定义。实算：amplitude 要涨到 1.12 才红。
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
    // 这条守的不是「初始化会不会报错」——实测 12 种头部变异，`AVAudioPlayer(data:)`
    // **一次都没抛过**。它守的是 fmt 块**数值字段被播放器怎么解释**：
    // 位深写成 8、采样率字段写成 22050、声道写成 2、fmt 块长度写成 18、格式写成浮点——
    // 这五种错**一个字节都不多不少**，长度、声明、削顶、衰减四条断言全对得上号，
    // 只有播放器报出来的时长会翻倍减半、或者 `prepareToPlay()` 返回 false。
    // 所以断言必须落在 `prepareToPlay()` 和 `duration` 上，指望初始化器是没用的。
    let player = try AVAudioPlayer(data: ClickSound.wavData())
    #expect(player.prepareToPlay())
    #expect(abs(player.duration - ClickSound.durationSeconds) < 0.003,
            "时长 \(player.duration)，期望约 \(ClickSound.durationSeconds)")
}

@Test @MainActor func 计数音不掐断用户正在放的念佛机() {
    // §6.2 的硬要求，也是「不用系统声、绕道自己合成 WAV」这整个设计的全部理由：
    // `AudioServicesPlaySystemSound` 不受类目管辖，混不了音。
    // 很多师兄一边放念佛机一边跟着计数，掐断它就是砸场子。
    //
    // 类目和选项都是**可读属性**，所以这条不需要给 AVAudioSession 造任何协议假件。
    // 它同时钉住两件事：`.ambient` 别被改成 `.playback`（「这样静音时也能响」
    // 是个很有诱惑力的错误），以及配置失败时别把「我试过了」当成「配好了」。
    Feedback.shared.prepare()
    #expect(AVAudioSession.sharedInstance().category == .ambient)
    #expect(AVAudioSession.sharedInstance().categoryOptions.contains(.mixWithOthers))
}
