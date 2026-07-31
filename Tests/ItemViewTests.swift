import Testing
import SwiftUI
import SwiftData
import Foundation
@testable import WiseWalk

@MainActor
@Test func 定课列表页能实例化() throws {
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    _ = ItemListView(store: env.items, path: .constant(NavigationPath()))
}

@MainActor
@Test func 定课编辑页能实例化() throws {
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    _ = ItemEditorView(vm: ItemEditorViewModel(store: env.items))
}

@MainActor
@Test func 目标不影响历史的说明是明写出来的() {
    // spec §6.6 点名要求「须在 UI 上明示」。
    // 这条测试锁住那句话真的存在且提到了「以前」——
    // 光有代码里的注释，用户是看不见的。
    let note = ItemEditorView.goalDisclaimer
    #expect(!note.isEmpty)
    #expect(note.contains("以前"))
}

@MainActor
@Test func 归档的说明讲清了记录还在() {
    // 用户会以为归档 = 删除。PracticeItem 只归档不硬删，
    // 正是因为硬删会让流水变孤儿、被所有 per-item 查询挡在外面、静默蒸发。
    let note = ItemListView.archiveDisclaimer
    #expect(!note.isEmpty)
    #expect(note.contains("记录"))
}

@MainActor
@Test func 拖拽排序会落盘并按新序读回() throws {
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    for n in ["念佛", "持咒", "拜佛"] {
        _ = try env.items.create(name: n, measureType: .count, unit: "遍", dailyGoal: nil,
                                 iconName: "circle.grid.3x3", colorHex: Palette.Light.fulfilled)
    }
    var list = try env.items.activeItems()
    list.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
    try env.items.reorder(list)
    #expect(try env.items.activeItems().map(\.name) == ["拜佛", "念佛", "持咒"])
}

@MainActor
@Test func 归档后能恢复且回到列表里() throws {
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let item = try env.items.create(name: "念佛", measureType: .count, unit: "声", dailyGoal: nil,
                                    iconName: "circle.grid.3x3", colorHex: Palette.Light.fulfilled)
    try env.items.archive(item)
    #expect(try env.items.activeItems().isEmpty)
    #expect(try env.items.archivedItems().map(\.id) == [item.id])
    try env.items.unarchive(item)
    #expect(try env.items.activeItems().map(\.id) == [item.id])
}
