import Foundation
import UserNotifications

/// 倒计时到零时的引磬通知。§6.3.1。
///
/// **账绝不依赖它。** 到零那一刻 App 若已被系统杀掉、用户关了权限、开了专注模式，
/// 引磬都不会响。走时与入账全部由 `now − startedAt` 现算，与响没响毫无关系——
/// **引磬只是提醒，不是记账凭据。**
///
/// 权限**延后到用户第一次真的设倒计时**时才要，不在启动时弹。
/// 被拒绝就降级成「只在前台响」，并当场告诉用户——不能让他坐完才发现没响。
@MainActor
enum QingScheduler {
    /// **固定标识符。** `start()` 是幂等的、回前台会再调一次；
    /// 每次新建一个请求的话，回前台五次就排了五声引磬。
    /// 固定 id 让后来的请求顶掉前一个。
    static let requestID = "wisewalk.qing.countdown"

    /// `UNNotificationSound(named:)` 只认 App bundle 或 `Library/Sounds/` 里的文件，
    /// 喂不进内存里的 `Data`——所以合成出来之后得先落一次盘。
    static let soundFileName = "qing.wav"

    /// 把合成的引磬写进 `Library/Sounds/`。已存在就不重写。
    /// 失败返回 nil，调用方降级为默认通知音——**不是**不发通知。
    @discardableResult
    static func installSound() -> String? {
        guard let library = FileManager.default.urls(for: .libraryDirectory,
                                                     in: .userDomainMask).first
        else { return nil }
        let dir = library.appendingPathComponent("Sounds", isDirectory: true)
        let file = dir.appendingPathComponent(soundFileName)
        if FileManager.default.fileExists(atPath: file.path) { return soundFileName }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try QingSound.wavData().write(to: file, options: .atomic)
            return soundFileName
        } catch {
            return nil
        }
    }

    /// 请求权限。**只在用户第一次真的设倒计时时调。**
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// 排一声引磬在 `after` 秒之后。重复调用会顶掉上一次。
    static func schedule(after seconds: Int, itemName: String, sound: Bool) {
        cancel()
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = itemName
        content.body = "时间到"
        if sound {
            content.sound = installSound().map {
                UNNotificationSound(named: UNNotificationSoundName($0))
            } ?? .default
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds),
                                                        repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: requestID, content: content, trigger: trigger)
        )
    }

    /// 撤掉已排的引磬。
    ///
    /// ⛔ **`finish` / `record` / `abandon` 三个出口都要调。**
    /// 用户设 30 分钟、10 分钟就下坐了，20 分钟后手机突然响一声——必现的骚扰。
    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [requestID])
    }
}
