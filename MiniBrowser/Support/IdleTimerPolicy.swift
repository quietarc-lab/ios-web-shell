import Foundation

/// Decides when the foreground scene should keep the device's idle timer
/// disabled for an in-progress automatic posting operation.
enum IdleTimerPolicy {
    static func shouldDisableIdleTimer(appIsActive: Bool,
                                        automaticFlowIsActive: Bool,
                                        repeatSessionIsActive: Bool,
                                        responseVerificationIsActive: Bool) -> Bool {
        appIsActive && (automaticFlowIsActive ||
                        repeatSessionIsActive ||
                        responseVerificationIsActive)
    }
}
