import Testing
import AVFoundation
import Foundation
@testable import WiseWalk

@Test func 引磬WAV能被AVAudioPlayer接受() throws {
    // 头部任何一个数值字段填错，多半不会抛错、只会让声音闷掉或变调。
    // 所以除了「构造得出来」，下面几条还要各自钉住一个字段。
    let player = try AVAudioPlayer(data: QingSound.wavData())
    #expect(player.prepareToPlay())
    #expect(player.numberOfChannels == 1)
    #expect(abs(player.duration - QingSound.durationSeconds) < 0.05,
            "时长对不上说明采样率或位深写错了")
}

@Test func 引磬比点击声长得多() {
    // 点击声 8 毫秒，引磬要有余韵。两者共用 WAVWriter，
    // 若哪天有人把 durationSeconds 接错了源，这条会红。
    #expect(QingSound.durationSeconds > 1.0)
    #expect(QingSound.durationSeconds > ClickSound.durationSeconds * 100)
}

@Test func 引磬的泛音不落在整数倍上() {
    // 非谐是磬听起来像金属而不像笛子的原因。
    // 有人「顺手把比例改整齐」的话，这条会红。
    for p in QingSound.partials.dropFirst() {
        let nearestInteger = (p.ratio).rounded()
        #expect(abs(p.ratio - nearestInteger) > 0.01,
                "倍数 \(p.ratio) 落在整数倍上，磬就变成风琴了")
    }
}

@Test func 引磬采样不削顶() {
    // 五个泛音叠加很容易推过 1.0。削顶的正弦听起来是爆音不是磬声。
    let data = QingSound.wavData()
    let pcm = data.dropFirst(44)
    var maxAbs: Int32 = 0
    for i in stride(from: 0, to: pcm.count - 1, by: 2) {
        let lo = Int32(pcm[pcm.startIndex + i])
        let hi = Int32(Int8(bitPattern: pcm[pcm.startIndex + i + 1]))
        let sample = (hi << 8) | lo
        maxAbs = max(maxAbs, abs(sample))
    }
    #expect(maxAbs < 32_767, "削顶了")
    #expect(maxAbs > 3_000, "太轻，等于没响")
}

@Test func 引磬结尾接近静音() {
    // 硬截断会在结尾产生一声爆响。
    let data = QingSound.wavData()
    let pcm = Array(data.dropFirst(44))
    func amplitude(around index: Int) -> Int32 {
        var m: Int32 = 0
        for i in stride(from: index, to: min(index + 2000, pcm.count - 1), by: 2) {
            let lo = Int32(pcm[i])
            let hi = Int32(Int8(bitPattern: pcm[i + 1]))
            m = max(m, abs((hi << 8) | lo))
        }
        return m
    }
    let head = amplitude(around: 200)
    let tail = amplitude(around: pcm.count - 2200)
    #expect(tail * 20 < head, "结尾振幅必须比开头小一大截")
}

@Test func 两个音源共用同一份WAV头() {
    // WAVWriter 抽出来就是为了不让两份头部各错各的。
    // 这条钉住「确实共用了」——各写各的实现会让某个字段分家。
    let click = ClickSound.wavData()
    let qing = QingSound.wavData()
    #expect(Array(click[0..<4]) == Array("RIFF".utf8))
    #expect(Array(qing[0..<4]) == Array("RIFF".utf8))
    // 采样率相同，则 8..36 这段格式头应当逐字节相同（只有 data 长度不同）。
    #expect(ClickSound.sampleRate == QingSound.sampleRate, "前提：两者采样率相同")
    #expect(Array(click[8..<36]) == Array(qing[8..<36]))
}
