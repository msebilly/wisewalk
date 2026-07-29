import Testing
import Foundation
@testable import WiseWalk

@Test func 短码稳定不变() {
    let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    let first = DeviceIdentity.shortCode(defaults: defaults)
    let second = DeviceIdentity.shortCode(defaults: defaults)
    #expect(first == second, "同一台设备的短码必须稳定，否则诊断页会把一台设备算成两台")
    #expect(first.count == 4)
}

@Test func 不同存储生成不同短码() {
    let a = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    let b = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    #expect(DeviceIdentity.shortCode(defaults: a) != DeviceIdentity.shortCode(defaults: b))
}

@Test func 短码只含大写字母与数字() {
    let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    let code = DeviceIdentity.shortCode(defaults: defaults)
    let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    #expect(code.allSatisfy { allowed.contains($0) })
}

@Test func 显示名包含机型与短码() async {
    let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    let name = await DeviceIdentity.displayName(defaults: defaults)
    #expect(name.contains("·"))
    let parts = name.split(separator: "·")
    #expect(parts.count == 2)
    #expect(parts[1].count == 4)
}
