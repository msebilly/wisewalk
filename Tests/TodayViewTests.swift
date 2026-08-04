import Testing
import SwiftUI
import SwiftData
import Foundation
@testable import WiseWalk

@MainActor
@Test func 按量法给出对应的去处() {
    let id = UUID()
    #expect(Route.forRecording(measureType: .count, itemID: id) == .counter(id))
    #expect(Route.forRecording(measureType: .duration, itemID: id) == .timer(id))
    #expect(Route.forRecording(measureType: .check, itemID: id) == nil,
            "勾选类就地打勾，不另开页面")
}

@MainActor
@Test func 路由可哈希可用于导航栈() {
    // NavigationStack 的 path 要求 Hashable，不满足会在运行时才炸。
    let s: Set<Route> = [.counter(UUID()), .timer(UUID()), .manualEntry, .itemList]
    #expect(s.count == 4)
}

@MainActor
@Test func 今日页能实例化() throws {
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    _ = TodayView(vm: TodayViewModel(ledger: env.ledger, items: env.items),
                  settings: env.settings, path: .constant(NavigationPath()),
                  syncStatus: env.syncStatus)
}

struct TodaySyncStatusTests {
    @MainActor
    @Test func 底部状态栏与读屏只陈述账户不可用或当前本地路径() {
        let 每一档: [(LedgerSyncStatus, String)] = [
            (.noAccount, "这台设备目前无法使用 iCloud · 未登录 iCloud"),
            (.restricted, "这台设备目前无法使用 iCloud · iCloud 账户受限"),
            (.couldNotDetermine, "这台设备目前无法使用 iCloud · 无法确定 iCloud 账户状态"),
            (.temporarilyUnavailable, "这台设备目前无法使用 iCloud · iCloud 暂时不可用"),
            (.accountLookupFailed(reason: "账户服务超时"),
             "这台设备目前无法使用 iCloud · 无法查询 iCloud 账户"),
            (.localOnly(reason: "数据库打不开"),
             "当前使用本地账本 · iCloud 数据库未能打开"),
            (.localOnly(reason: nil), "当前使用本地账本 · 未启用 iCloud")
        ]

        for (状态, 事实) in 每一档 {
            _ = BackupStatusBar(status: 状态)
            #expect(状态.barText == 事实,
                    "BackupStatusBar 的可见文字与 accessibilityLabel 都从 barText 读取")
        }
    }
}

@MainActor
@Test func 无定课时是空态不是圆满() throws {
    // 一项功课都没立就说「今日圆满」，是对用户的欺骗。
    let ctx = ModelContext(try ModelContainerFactory.inMemory())
    let vm = TodayViewModel(ledger: DayLedger(context: ctx, deviceName: "T"),
                            items: PracticeItemStore(context: ctx))
    try vm.reload()
    #expect(vm.rows.isEmpty)
    #expect(!vm.isFulfilled)
    #expect(vm.isRestDay)
}
