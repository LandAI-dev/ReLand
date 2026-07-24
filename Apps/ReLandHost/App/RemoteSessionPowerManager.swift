import Foundation
import IOKit.pwr_mgt

final class RemoteSessionPowerManager: @unchecked Sendable {
    private static let activityReason =
        "ReLand remote screen session"

    private let lock = NSLock()
    private var displaySleepAssertionID =
        IOPMAssertionID(kIOPMNullAssertionID)
    private var systemSleepAssertionID =
        IOPMAssertionID(kIOPMNullAssertionID)
    private var userActivityAssertionID =
        IOPMAssertionID(kIOPMNullAssertionID)

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return displaySleepAssertionID != kIOPMNullAssertionID
            || systemSleepAssertionID != kIOPMNullAssertionID
    }

    func setRemoteSessionActive(_ isActive: Bool) throws {
        lock.lock()
        defer { lock.unlock() }

        if isActive {
            try createSessionAssertions()
            try declareUserActivity()
        } else {
            try releaseAssertions()
        }
    }

    func noteRemoteUserActivity() throws {
        lock.lock()
        defer { lock.unlock() }
        try declareUserActivity()
    }

    private func createSessionAssertions() throws {
        var createdDisplayAssertion = false
        if displaySleepAssertionID == kIOPMNullAssertionID {
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertPreventUserIdleDisplaySleep
                    as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                Self.activityReason as CFString,
                &displaySleepAssertionID
            )
            guard result == kIOReturnSuccess else {
                throw RemoteSessionPowerError.createDisplay(result)
            }
            createdDisplayAssertion = true
        }

        guard systemSleepAssertionID == kIOPMNullAssertionID else {
            return
        }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep
                as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            Self.activityReason as CFString,
            &systemSleepAssertionID
        )
        guard result == kIOReturnSuccess else {
            if createdDisplayAssertion {
                let releaseResult = IOPMAssertionRelease(
                    displaySleepAssertionID
                )
                if releaseResult == kIOReturnSuccess {
                    displaySleepAssertionID =
                        IOPMAssertionID(kIOPMNullAssertionID)
                } else {
                    throw RemoteSessionPowerError.releaseDisplay(
                        releaseResult
                    )
                }
            }
            throw RemoteSessionPowerError.createSystem(result)
        }
    }

    private func declareUserActivity() throws {
        var assertionID = userActivityAssertionID
        let result = IOPMAssertionDeclareUserActivity(
            Self.activityReason as CFString,
            kIOPMUserActiveRemote,
            &assertionID
        )
        guard result == kIOReturnSuccess else {
            throw RemoteSessionPowerError.userActivity(result)
        }
        userActivityAssertionID = assertionID
    }

    private func releaseAssertions() throws {
        var firstError: RemoteSessionPowerError?

        if userActivityAssertionID != kIOPMNullAssertionID {
            let result = IOPMAssertionRelease(
                userActivityAssertionID
            )
            if result == kIOReturnSuccess {
                userActivityAssertionID =
                    IOPMAssertionID(kIOPMNullAssertionID)
            } else {
                firstError = .releaseUserActivity(result)
            }
        }

        if displaySleepAssertionID != kIOPMNullAssertionID {
            let result = IOPMAssertionRelease(
                displaySleepAssertionID
            )
            if result == kIOReturnSuccess {
                displaySleepAssertionID =
                    IOPMAssertionID(kIOPMNullAssertionID)
            } else if firstError == nil {
                firstError = .releaseDisplay(result)
            }
        }

        if systemSleepAssertionID != kIOPMNullAssertionID {
            let result = IOPMAssertionRelease(
                systemSleepAssertionID
            )
            if result == kIOReturnSuccess {
                systemSleepAssertionID =
                    IOPMAssertionID(kIOPMNullAssertionID)
            } else if firstError == nil {
                firstError = .releaseSystem(result)
            }
        }

        if let firstError {
            throw firstError
        }
    }
}

private enum RemoteSessionPowerError: LocalizedError {
    case createDisplay(IOReturn)
    case createSystem(IOReturn)
    case userActivity(IOReturn)
    case releaseDisplay(IOReturn)
    case releaseSystem(IOReturn)
    case releaseUserActivity(IOReturn)

    var errorDescription: String? {
        switch self {
        case let .createDisplay(code):
            "ReLand could not keep the Mac display awake "
                + "(power error \(code))."
        case let .createSystem(code):
            "ReLand could not keep the Mac available "
                + "(power error \(code))."
        case let .userActivity(code):
            "The Mac display could not be woken "
                + "(power error \(code))."
        case let .releaseDisplay(code),
             let .releaseSystem(code),
             let .releaseUserActivity(code):
            "ReLand could not restore the Mac sleep policy "
                + "(power error \(code))."
        }
    }
}
