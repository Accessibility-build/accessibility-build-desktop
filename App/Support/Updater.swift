import Foundation
import Sparkle

/// Sparkle, configured in Info.plist: the feed is
/// https://accessibility.build/desktop/appcast.xml, updates must carry an
/// EdDSA signature matching SUPublicEDKey, and system profiling is off.
/// Sparkle asks the user on second launch before checking automatically.
@MainActor
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updater()
    private var controller: SPUStandardUpdaterController?

    func start() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Set when Sparkle found an update in the background but did not put
    /// its window in front; the menu then offers "Update Available…".
    private(set) var updateAvailable = false

    // A menu-bar app has no Dock icon to badge, so scheduled updates are
    // shown gently and flagged in the menu until the user looks at them.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        MainActor.assumeIsolated {
            if !state.userInitiated { updateAvailable = true }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { updateAvailable = false }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { updateAvailable = false }
    }
}
