import Testing
import Foundation
@testable import WiseWalk

private func 干净的偏好() -> UserDefaults {
    let name = "test.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

@MainActor
@Test func 音效与震动默认都开() {
    let s = AppSettings(defaults: 干净的偏好())
    #expect(s.soundEnabled)
    #expect(s.hapticEnabled)
}

@MainActor
@Test func 音效与震动互不影响() {
    // §6.2：两个开关必须独立。有人在公共场合只要震动，有人戴手套只要声音。
    let d = 干净的偏好()
    let s = AppSettings(defaults: d)
    s.soundEnabled = false
    #expect(!s.soundEnabled)
    #expect(s.hapticEnabled, "关掉音效不该把震动一起关掉")

    s.hapticEnabled = false
    s.soundEnabled = true
    #expect(s.soundEnabled)
    #expect(!s.hapticEnabled)
}

@MainActor
@Test func 三个设置都能跨实例持久() {
    // **三个都得验。** 从前只验了 soundEnabled，于是另外两个的 setter
    // 若忘了那句 `defaults.set(...)`，全卷没有一条测试会红：
    // 底下 `一日起始…` 与 `音效与震动互不影响` 读的都是同一个实例的内存。
    //
    // dayStartHour 丢了最要命。用户把一日起始设成 4 点，是因为他夜里
    // 十一点做晚课、做到凌晨一点，心里那是「今天」的课。设置一丢回到 0 点，
    // 那一坐就记到了新的一天——**昨天变成没圆满，今天凭空多一笔**。
    // 界面第 5 卷才开放，但这条测试现在就得立着。
    let d = 干净的偏好()
    let 头一回 = AppSettings(defaults: d)
    头一回.soundEnabled = false
    头一回.hapticEnabled = false
    头一回.dayStartHour = 4

    let 重启后 = AppSettings(defaults: d)
    #expect(!重启后.soundEnabled, "重启后音效设置丢了")
    #expect(!重启后.hapticEnabled, "重启后震动设置丢了")
    #expect(重启后.dayStartHour == 4, "重启后一日起始丢了，晚课会记到第二天")
}

@MainActor
@Test func 一日起始默认零点且只收0到6() {
    // 允许把「一天」推后几小时，为的是夜里十一点做完晚课的人。
    // 超过 6 点就荒唐了——那会让上午的功课记到前一天。
    let s = AppSettings(defaults: 干净的偏好())
    #expect(s.dayStartHour == 0)
    s.dayStartHour = 4
    #expect(s.dayStartHour == 4)
    s.dayStartHour = 9
    #expect(s.dayStartHour == 6, "越界该夹到上限")
    s.dayStartHour = -3
    #expect(s.dayStartHour == 0, "越界该夹到下限")
}
