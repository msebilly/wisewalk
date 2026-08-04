import CloudKit
import CoreFoundation
import Security

private typealias SecTaskRef = CFTypeRef

@_silgen_name("SecTaskCreateFromSelf")
private func SecTaskCreateFromSelf(_ allocator: CFAllocator?) -> Unmanaged<SecTaskRef>?

@_silgen_name("SecTaskCopyValueForEntitlement")
private func SecTaskCopyValueForEntitlement(
    _ task: SecTaskRef,
    _ entitlement: CFString,
    _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?
) -> Unmanaged<CFTypeRef>?

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

enum CloudKitEntitlementValue: Equatable, Sendable {
    case missing
    case invalid
    case containers([String])

    var includesRequiredContainer: Bool {
        guard case .containers(let identifiers) = self else { return false }
        return identifiers.contains("iCloud.com.msebilly.wisewalk")
    }

    init(_ value: Any?) {
        guard let value else {
            self = .missing
            return
        }
        guard let identifiers = value as? [String] else {
            self = .invalid
            return
        }
        self = .containers(identifiers)
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
        cloudKitEntitlement: processCloudKitEntitlement,
        accountStatus: {
            let status = try await CKContainer(
                identifier: "iCloud.com.msebilly.wisewalk"
            ).accountStatus()
            return CloudAccountAvailability(status)
        }
    )

    static func guarded(
        cloudKitEntitlement: @escaping @Sendable () -> CloudKitEntitlementValue,
        accountStatus: @escaping @Sendable () async throws -> CloudAccountAvailability
    ) -> Self {
        Self {
            guard cloudKitEntitlement().includesRequiredContainer else {
                throw CloudAccountStatusError.missingEntitlement
            }
            return try await accountStatus()
        }
    }

    static func hasRequiredICloudContainer(in entitlementValue: Any?) -> Bool {
        CloudKitEntitlementValue(entitlementValue).includesRequiredContainer
    }

    private static func processCloudKitEntitlement() -> CloudKitEntitlementValue {
        guard let task = SecTaskCreateFromSelf(nil)?.takeRetainedValue() else {
            return .missing
        }

        guard let copied = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.developer.icloud-container-identifiers" as CFString,
            nil
        ) else {
            return .missing
        }
        let value = copied.takeRetainedValue()
        return CloudKitEntitlementValue(value)
    }
}
