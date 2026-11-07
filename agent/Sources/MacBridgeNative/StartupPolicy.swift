import Foundation
import ServiceManagement

/// Decides how Wand keeps itself running. Pure functions so tests cover them without touching launchd.
///
/// Wand used to be a plain login item (`SMAppService.mainApp`), which only starts the app at login.
/// It is now a keep-alive LaunchAgent embedded in the bundle, so a crash, a kill or a quit brings it back.
public enum StartupPolicy {
    public static let agentLabel = "local.macbridge.agent.keepalive"
    public static let agentPlistName = agentLabel + ".plist"
    /// launchd sets this for the keep-alive job (see agent/LaunchAgents); a manual launch never carries it.
    public static let keepAliveEnvironmentKey = "MACBRIDGE_KEEPALIVE"
    /// Set on a copy started to replace a launchd copy that is about to stop; it waits for that pid first.
    public static let handoffEnvironmentKey = "MACBRIDGE_HANDOFF_FROM_PID"
    /// Posted by a copy that steps aside so the running copy shows its window instead.
    public static let showWindowNotification = "local.macbridge.agent.show-window"

    public struct Migration: Equatable, Sendable {
        public let unregisterLoginItem: Bool
        public let registerAgent: Bool
        public init(unregisterLoginItem: Bool, registerAgent: Bool) {
            self.unregisterLoginItem = unregisterLoginItem; self.registerAgent = registerAgent
        }
    }

    /// One-time move from the old login item to the keep-alive agent. `nil` means nothing to do.
    ///
    /// Startup stays on only if the user had it on. A login item the user turned off in System Settings
    /// (`requiresApproval`) is removed without replacing it, and a toggle the user turned off in Wand
    /// (`notRegistered` after an attempt) stays off: Wand never re-enables itself after the user says no.
    public static func migration(loginItem: SMAppService.Status, attempted: Bool, migrated: Bool) -> Migration? {
        guard !migrated else { return nil }
        switch loginItem {
        case .enabled: return Migration(unregisterLoginItem: true, registerAgent: true)
        case .requiresApproval: return Migration(unregisterLoginItem: true, registerAgent: false)
        default: return Migration(unregisterLoginItem: false, registerAgent: !attempted)
        }
    }

    public enum LaunchDecision: Equatable, Sendable {
        /// No other copy is running.
        case proceed
        /// A copy is already running; ask it to show its window and exit.
        case handOff
        /// This copy belongs to launchd, which would restart it forever if it exited; the others step aside.
        case takeOver
    }

    public static func launchDecision(managedByLaunchd: Bool, otherInstances: Int) -> LaunchDecision {
        guard otherInstances > 0 else { return .proceed }
        return managedByLaunchd ? .takeOver : .handOff
    }

    public static func message(for status: SMAppService.Status) -> String {
        switch status {
        case .enabled: return "Starts when you log in and comes back by itself if it quits or crashes."
        case .requiresApproval: return "Allow Wand in System Settings → General → Login Items so it can stay running."
        case .notRegistered: return "Off. Wand stays closed after a quit or restart until you open it yourself."
        case .notFound: return "Move Wand to Applications, then turn this setting on."
        @unknown default: return "Check Wand in System Settings → General → Login Items."
        }
    }
}
