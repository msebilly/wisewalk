import CloudKit
import Foundation
import SwiftData
import Testing
@testable import WiseWalk

private enum AccountLookupFailure: LocalizedError, Sendable {
    case offline

    var errorDescription: String? { "无法连接账户服务" }
}

private actor AccountStateSequence {
    private var values: [CloudAccountAvailability]
    private var calls = 0
    private var secondCallWaiter: CheckedContinuation<Void, Never>?

    init(_ values: [CloudAccountAvailability]) {
        self.values = values
    }

    func next() -> CloudAccountAvailability {
        calls += 1
        if calls == 2 {
            secondCallWaiter?.resume()
            secondCallWaiter = nil
        }
        return values.removeFirst()
    }

    func waitForSecondCall() async {
        guard calls < 2 else { return }
        await withCheckedContinuation { secondCallWaiter = $0 }
    }
}

private actor AccountLookupProbe {
    private(set) var calls = 0

    func recordCall() {
        calls += 1
    }
}

private actor PendingAccountLookups {
    private var continuations: [CheckedContinuation<CloudAccountAvailability, Never>] = []

    func fetch() async -> CloudAccountAvailability {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitForCount(_ expected: Int) async {
        while continuations.count < expected {
            await Task.yield()
        }
    }

    func resolve(_ index: Int, with value: CloudAccountAvailability) {
        continuations[index].resume(returning: value)
    }
}

struct CloudAccountStatusTests {
    @Test func deviceTargetWithoutExplicitBuildVerificationRemainsUnverified() {
        #expect(CloudAccountStatusClient.buildVerification(
            explicitlyVerified: false,
            isSimulator: false
        ) == .unverified)
    }

    @Test func everyCloudKitAccountStatusMapsToAFactualAppState() {
        #expect(CloudAccountAvailability(CKAccountStatus.available) == .available)
        #expect(CloudAccountAvailability(CKAccountStatus.noAccount) == .noAccount)
        #expect(CloudAccountAvailability(CKAccountStatus.restricted) == .restricted)
        #expect(CloudAccountAvailability(CKAccountStatus.couldNotDetermine) == .couldNotDetermine)
        #expect(CloudAccountAvailability(CKAccountStatus.temporarilyUnavailable) == .temporarilyUnavailable)
    }

    @MainActor
    @Test func thrownAccountLookupBecomesAnExplicitErrorState() async throws {
        let opened = LedgerOpen(container: try ModelContainerFactory.inMemory(),
                                sync: .iCloud,
                                fallbackReason: nil)
        let monitor = LedgerSyncStatusMonitor(
            opened: opened,
            accountClient: CloudAccountStatusClient {
                throw AccountLookupFailure.offline
            },
            notificationCenter: NotificationCenter()
        )

        await monitor.refresh()

        #expect(monitor.status == .accountLookupFailed(reason: "无法连接账户服务"))
        #expect(monitor.status.barText == "这台设备目前无法使用 iCloud · 无法查询 iCloud 账户")
    }

    @MainActor
    @Test func accountChangedNotificationRefreshesTheStatus() async throws {
        let center = NotificationCenter()
        let states = AccountStateSequence([.available, .noAccount])
        let opened = LedgerOpen(container: try ModelContainerFactory.inMemory(),
                                sync: .iCloud,
                                fallbackReason: nil)
        let monitor = LedgerSyncStatusMonitor(
            opened: opened,
            accountClient: CloudAccountStatusClient {
                await states.next()
            },
            notificationCenter: center
        )
        await monitor.refresh()
        #expect(monitor.status == .available)

        center.post(name: .CKAccountChanged, object: nil)
        await states.waitForSecondCall()
        for _ in 0..<20 where monitor.status != .noAccount {
            await Task.yield()
        }

        #expect(monitor.status == .noAccount)
        #expect(monitor.status.barText == "这台设备目前无法使用 iCloud · 未登录 iCloud")
    }

    @Test func unsignedOrUnverifiedBuildFailsWithoutCreatingACloudKitContainer() async {
        let probe = AccountLookupProbe()
        let client = CloudAccountStatusClient.livePolicy(
            isVerifiedSignedDeviceBuild: false,
            accountStatus: {
                await probe.recordCall()
                return .available
            }
        )

        await #expect(throws: CloudAccountStatusError.unsignedOrUnverifiedBuild) {
            _ = try await client.fetch()
        }
        #expect(await probe.calls == 0)
    }

    @Test func verifiedSignedDeviceBuildUsesTheInjectedPublicAccountLookup() async throws {
        let probe = AccountLookupProbe()
        let client = CloudAccountStatusClient.livePolicy(
            isVerifiedSignedDeviceBuild: true,
            accountStatus: {
                await probe.recordCall()
                return .available
            }
        )

        #expect(try await client.fetch() == .available)
        #expect(await probe.calls == 1)
    }

    @Test func publicAccountLookupFailureBecomesAnExplicitClientError() async {
        let client = CloudAccountStatusClient.livePolicy(
            isVerifiedSignedDeviceBuild: true,
            accountStatus: {
                throw AccountLookupFailure.offline
            }
        )

        await #expect(throws: CloudAccountStatusError.accountLookupFailed(
            reason: "无法连接账户服务"
        )) {
            _ = try await client.fetch()
        }
    }

    @MainActor
    @Test func staleAccountLookupCannotOverwriteANewerAccountChange() async throws {
        let lookups = PendingAccountLookups()
        let opened = LedgerOpen(container: try ModelContainerFactory.inMemory(),
                                sync: .iCloud,
                                fallbackReason: nil)
        let monitor = LedgerSyncStatusMonitor(
            opened: opened,
            accountClient: CloudAccountStatusClient { await lookups.fetch() },
            notificationCenter: NotificationCenter()
        )

        let older = Task { @MainActor in await monitor.refresh() }
        await lookups.waitForCount(1)
        let newer = Task { @MainActor in await monitor.refresh() }
        await lookups.waitForCount(2)

        await lookups.resolve(1, with: .noAccount)
        await newer.value
        await lookups.resolve(0, with: .available)
        await older.value

        #expect(monitor.status == .noAccount)
    }
}
