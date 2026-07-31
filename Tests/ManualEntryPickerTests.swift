import Testing
import SwiftData
import Foundation
@testable import WiseWalk

@MainActor
private func makePicker() throws -> (ManualEntryViewModel, PracticeItemStore) {
    let ctx = ModelContext(try ModelContainerFactory.inMemory())
    let ledger = DayLedger(context: ctx, deviceName: "iPhone·TEST")
    let items = PracticeItemStore(context: ctx)
    return (ManualEntryViewModel(ledger: ledger, items: items), items)
}

@MainActor
private func 造(_ items: PracticeItemStore, _ name: String) throws -> PracticeItem {
    try items.create(name: name, measureType: .count, unit: "声", dailyGoal: nil,
                     iconName: "circle.grid.3x3", colorHex: Palette.Light.fulfilled)
}

@MainActor
@Test func 清单按用户自己的排序给出() throws {
    let (vm, items) = try makePicker()
    let a = try 造(items, "念佛")
    let b = try 造(items, "持咒")
    let c = try 造(items, "拜佛")
    try items.reorder([c, a, b])

    try vm.reloadItems()
    #expect(vm.pickerItems.map(\.name) == ["拜佛", "念佛", "持咒"])
}

@MainActor
@Test func 清单不含已归档的项() throws {
    // 归档的功课不该还能往里补记新账。
    let (vm, items) = try makePicker()
    let a = try 造(items, "念佛")
    let b = try 造(items, "持咒")
    try items.archive(b)
    try vm.reloadItems()
    #expect(vm.pickerItems.map(\.id) == [a.id])
}

@MainActor
@Test func 加载后自动选中第一项省一次点击() throws {
    let (vm, items) = try makePicker()
    let a = try 造(items, "念佛")
    try vm.reloadItems()
    #expect(vm.selectedItem?.id == a.id)
}

@MainActor
@Test func 已选中的项在重载后保持不变() throws {
    // 用户选好了「持咒」，重载一下就跳回「念佛」是很恼人的。
    let (vm, items) = try makePicker()
    _ = try 造(items, "念佛")
    let b = try 造(items, "持咒")
    try vm.reloadItems()
    vm.selectedItem = b
    try vm.reloadItems()
    #expect(vm.selectedItem?.id == b.id)
}

@MainActor
@Test func 选中的项被归档后自动落回第一项() throws {
    // 不落回的话会停在一个已归档的项上，提交时静默失败。
    let (vm, items) = try makePicker()
    let a = try 造(items, "念佛")
    let b = try 造(items, "持咒")
    try vm.reloadItems()
    vm.selectedItem = b
    try items.archive(b)
    try vm.reloadItems()
    #expect(vm.selectedItem?.id == a.id)
}

@MainActor
@Test func 一项都没有时选中为空() throws {
    let (vm, _) = try makePicker()
    try vm.reloadItems()
    #expect(vm.pickerItems.isEmpty)
    #expect(vm.selectedItem == nil)
}
