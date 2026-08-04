import CloudKit

enum CloudAccountStatusError: LocalizedError, Equatable, Sendable {
    case unsignedOrUnverifiedBuild
    case accountLookupFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .unsignedOrUnverifiedBuild:
            "当前构建未签名或无法验证，不查询 iCloud 账户"
        case .accountLookupFailed(let reason):
            "iCloud 账户查询失败：\(reason)"
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

enum CloudAccountBuildVerification: Equatable, Sendable {
    case unverified
    case verifiedSignedDevice
}

struct CloudAccountStatusClient: Sendable {
    let fetch: @Sendable () async throws -> CloudAccountAvailability

    init(_ fetch: @escaping @Sendable () async throws -> CloudAccountAvailability) {
        self.fetch = fetch
    }

    /// iOS has no public API for inspecting applied entitlements at runtime.
    /// Simulator builds are therefore blocked before CloudKit is instantiated;
    /// a provisioned device build must also explicitly enable
    /// `WISEWALK_VERIFIED_CLOUDKIT_DEVICE` after code signing is configured.
    static let live = livePolicy(
        isVerifiedSignedDeviceBuild: liveBuildVerification == .verifiedSignedDevice,
        accountStatus: {
            let status = try await CKContainer.default().accountStatus()
            return CloudAccountAvailability(status)
        }
    )

    static func livePolicy(
        isVerifiedSignedDeviceBuild: Bool,
        accountStatus: @escaping @Sendable () async throws -> CloudAccountAvailability
    ) -> Self {
        Self {
            guard isVerifiedSignedDeviceBuild else {
                throw CloudAccountStatusError.unsignedOrUnverifiedBuild
            }
            do {
                return try await accountStatus()
            } catch {
                throw CloudAccountStatusError.accountLookupFailed(
                    reason: error.localizedDescription
                )
            }
        }
    }

    static func buildVerification(
        explicitlyVerified: Bool,
        isSimulator: Bool
    ) -> CloudAccountBuildVerification {
        guard explicitlyVerified, !isSimulator else { return .unverified }
        return .verifiedSignedDevice
    }

    private static var liveBuildVerification: CloudAccountBuildVerification {
        #if WISEWALK_VERIFIED_CLOUDKIT_DEVICE
        let explicitlyVerified = true
        #else
        let explicitlyVerified = false
        #endif

        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif

        return buildVerification(
            explicitlyVerified: explicitlyVerified,
            isSimulator: isSimulator
        )
    }
}
