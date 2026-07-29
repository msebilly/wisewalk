import Foundation
import UIKit

/// 流水的落款。诊断页据此回答「这笔账是哪台设备记的」。
///
/// iOS 16 起 `UIDevice.current.name` 在没有特殊 entitlement 时只返回通用机型名，
/// 所以补一个本机随机短码来区分同型号的多台设备。
/// 短码存在本机 UserDefaults，**不进 CloudKit**——它描述的是设备而不是数据。
enum DeviceIdentity {
    private static let storageKey = "device.shortCode"
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    /// 本机四位短码，首次调用时生成并持久化。
    static func shortCode(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: storageKey), existing.count == 4 {
            return existing
        }
        let code = String((0..<4).map { _ in alphabet.randomElement()! })
        defaults.set(code, forKey: storageKey)
        return code
    }

    /// 形如 `iPhone·A3K9`
    ///
    /// `UIDevice` 在 SDK 里标了 `NS_SWIFT_UI_ACTOR`，严格并发下取机型必须在主线程，
    /// 所以这里如实标 `@MainActor` 而不是绕开。调用方 `DayLedger` 本就是 `@MainActor`。
    @MainActor
    static func displayName(defaults: UserDefaults = .standard) -> String {
        "\(UIDevice.current.model)·\(shortCode(defaults: defaults))"
    }
}
