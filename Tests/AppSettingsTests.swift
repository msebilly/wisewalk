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
    // **两个开关必须给不同的值。** 从前这里把 sound 和 haptic 都写成 false，
    // 于是一个「haptic 读的是 sound 那个键」的实现照样绿——两个都 false，
    // 读串了也看不出来。那个 bug 的方向是「多」：用户关掉音效，震动跟着一起没了，
    // 他敲了一下什么反馈都没有，以为没记上，于是又敲一下。
    头一回.soundEnabled = false
    头一回.hapticEnabled = true
    头一回.dayStartHour = 4

    let 重启后 = AppSettings(defaults: d)
    #expect(!重启后.soundEnabled, "重启后音效设置丢了")
    #expect(重启后.hapticEnabled, "重启后震动设置丢了，或者它读的是音效那个键")
    #expect(重启后.dayStartHour == 4, "重启后一日起始丢了，晚课会记到第二天")
}

@MainActor
@Test func 盘上已存的越界一日起始要在装配时夹回来() {
    // setter 会 clamp，但**盘上的值不经过 setter**。
    // 越界值进得来的路子有两条：旧版本写下的，以及第 3 卷接上
    // `NSUbiquitousKeyValueStore` 之后别的设备推过来的。
    //
    // 真让 9 点生效，用户上午做的功课会被记到**前一天**——
    // 昨天凭空多一笔，今天少一笔，两个方向一起错。
    //
    // 从前这条路没有守卫：`一日起始默认零点且只收0到6` 只走干净域（读到 0）
    // 和 setter 两条路，一个「init 不 clamp」的实现从这两条路都照不出来。
    let name = "test.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    d.set(9, forKey: "settings.dayStartHour")

    #expect(AppSettings(defaults: d).dayStartHour == 6, "盘上的越界值没夹到上限")

    d.set(-3, forKey: "settings.dayStartHour")
    #expect(AppSettings(defaults: d).dayStartHour == 0, "盘上的越界值没夹到下限")
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
