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
                  settings: env.settings, path: .constant(NavigationPath()))
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
