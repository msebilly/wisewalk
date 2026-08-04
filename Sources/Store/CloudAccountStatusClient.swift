import CloudKit

enum CloudAccountStatusError: LocalizedError, Equatable, Sendable {
    case missingEntitlement

    var errorDescription: String? {
        switch self {
        case .missingEntitlement:
            "当前构建没有启用 CloudKit entitlement"
        }
    }
}

enum CloudAccountAvailability: Equatable, Sendable {
    case available
    case noAccount
    case restricted
    case couldNotDetermine
    case temporarilyUnavailable

    init(_ status: CKAccountStatus) {
        switch status {
        case .available: self = .available
        case .noAccount: self = .noAccount
        case .restricted: self = .restricted
        case .couldNotDetermine: self = .couldNotDetermine
        case .temporarilyUnavailable: self = .temporarilyUnavailable
        @unknown default: self = .couldNotDetermine
        }
    }
}

struct CloudAccountStatusClient: Sendable {
    let fetch: @Sendable () async throws -> CloudAccountAvailability

    init(_ fetch: @escaping @Sendable () async throws -> CloudAccountAvailability) {
        self.fetch = fetch
    }

    /// The CKContainer path is present for a future signed device build, but these
    /// entitlements have not been exercised without a paid developer account.
    static let live = guarded(
        hasCloudKitEntitlement: processHasCloudKitEntitlement,
        accountStatus: {
            let status = try await CKContainer(
                identifier: "iCloud.com.msebilly.wisewalk"
            ).accountStatus()
            return CloudAccountAvailability(status)
        }
    )

    static func guarded(
        hasCloudKitEntitlement: @escaping @Sendable () -> Bool,
        accountStatus: @escaping @Sendable () async throws -> CloudAccountAvailability
    ) -> Self {
        Self {
            guard hasCloudKitEntitlement() else {
                throw CloudAccountStatusError.missingEntitlement
            }
            return try await accountStatus()
        }
    }

    private static func processHasCloudKitEntitlement() -> Bool {
        #if targetEnvironment(simulator)
        // This repository disables code signing, so simulator builds do not carry
        // the entitlement and CKContainer traps instead of returning an error.
        false
        #else
        // A device build cannot be installed until the configured entitlements
        // have been signed by the paid developer account.
        true
        #endif
    }
}
