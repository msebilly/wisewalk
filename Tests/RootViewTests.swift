import Testing
import SwiftUI
import SwiftData
import Foundation
@testable import WiseWalk

@MainActor
@Test func 根视图能实例化() throws {
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    _ = RootView(env: env)
}

@MainActor
@Test func 恢复弹窗的文案说清了是哪一项多少量() throws {
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let item = try env.items.create(name: "念佛", measureType: .count, unit: "声",
                                    dailyGoal: nil, iconName: "circle.grid.3x3",
                                    colorHex: Palette.Light.fulfilled)
    let now = Date()
    let draft = try env.drafts.begin(itemID: item.id, source: .counter, at: now)
    try env.drafts.update(draft, amount: 108, at: now)
    let rc = RecoveryCoordinator(env: env)
    try rc.runAtLaunch()

    let msg = RootView.recoveryMessage(rc.pending[0])
    #expect(msg.contains("念佛"))
    #expect(msg.contains("108 声"))
}

@MainActor
@Test func 恢复完成前不放行导航() throws {
    // 顺序依赖：清算没跑完就让用户进计时器，
    // TimerViewModel.start() 会承接那份三天前的草稿接着计时。
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let rc = RecoveryCoordinator(env: env)
    #expect(!rc.didRun)
    #expect(!RootView.isReady(rc), "没跑清算就放行是错的")
    try rc.runAtLaunch()
    #expect(RootView.isReady(rc))
}

@MainActor
@Test func 还有待裁决的草稿时也不放行() throws {
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let item = try env.items.create(name: "打坐", measureType: .duration, unit: "",
                                    dailyGoal: nil, iconName: "figure.mind.and.body",
                                    colorHex: Palette.Light.accent)
    let now = Date()
    let draft = try env.drafts.begin(itemID: item.id, source: .timer, at: now)
    try env.drafts.touch(draft, at: now.addingTimeInterval(600))
    let rc = RecoveryCoordinator(env: env)
    try rc.runAtLaunch()

    #expect(!RootView.isReady(rc), "还有草稿没裁决就进计时器，会接着三天前的计")
    try rc.discard(rc.pending[0])
    #expect(RootView.isReady(rc))
}
