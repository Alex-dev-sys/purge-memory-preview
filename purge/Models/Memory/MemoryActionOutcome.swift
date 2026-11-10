import Foundation

nonisolated enum MemoryAction: String, Codable, Sendable {
    case quit, forceQuit, clean
    var title: String {
        switch self {
        case .quit: memoryText("Quit")
        case .forceQuit: memoryText("Force Quit")
        case .clean: memoryText("Clean Memory")
        }
    }
}

nonisolated enum MemoryActionOutcome: String, Codable, Sendable {
    case terminated, requestRefused, timedOut, alreadyExited, identityChanged, policySkipped, cleaned, cleanFailed
    var title: String {
        switch self {
        case .terminated: memoryText("Terminated")
        case .requestRefused: memoryText("Request refused")
        case .timedOut: memoryText("Has not quit")
        case .alreadyExited: memoryText("Already exited")
        case .identityChanged: memoryText("Identity changed")
        case .policySkipped: memoryText("Skipped for safety")
        case .cleaned: memoryText("Memory cleaning finished")
        case .cleanFailed: memoryText("Memory cleaning failed")
        }
    }
}

nonisolated enum MemoryMeasurement: String, Codable, Sendable {
    case observed, belowThreshold, unmeasured
}

nonisolated enum MemoryActionReason: String, Codable, Sendable {
    case policyDenied, staleSample, targetGone, identityChanged, observationInterrupted
    case appExiting, samplingUnavailable, terminationNotObserved
}

nonisolated struct MemoryHistoryEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let date: Date
    let bundleID: String?
    let name: String
    let action: MemoryAction
    let outcome: MemoryActionOutcome
    let measurement: MemoryMeasurement
    let delta: Int64?
    let beforeDate: Date?
    let afterDate: Date?
    let accountingVersion: Int
    var reason: MemoryActionReason? = nil
    var cleanupTrigger: MemoryCleanupTrigger? = nil
    var beforeFree: Int64? = nil
    var afterFree: Int64? = nil
    var cleanupError: String? = nil
}

nonisolated struct MemoryConfirmation: Identifiable, Sendable {
    let id: UUID
    let action: MemoryAction
    let targets: [MemoryProcessGroup]
}
