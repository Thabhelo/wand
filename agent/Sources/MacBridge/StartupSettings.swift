import AppKit
import Foundation
import MacBridgeNative
import ServiceManagement

/// Wand stays running through a keep-alive LaunchAgent bundled at Contents/Library/LaunchAgents.
/// A login item only starts the app at login; the agent also brings it back after a crash, a kill or a quit.
@MainActor enum StartupSettings {
    private static let attemptedKey = "wand-login-registration-attempted"
    private static let migratedKey = "wand-keepalive-agent-migrated"
    private static let agent = SMAppService.agent(plistName: StartupPolicy.agentPlistName)
    /// True for the copy launchd started from the keep-alive job.
    static var managedByLaunchd: Bool { ProcessInfo.processInfo.environment[StartupPolicy.keepAliveEnvironmentKey] == "1" }
    private static var installed: Bool {
        let url = Bundle.main.bundleURL
        return url.pathExtension == "app" && !url.path.contains("/AppTranslocation/") && !url.path.hasPrefix("/Volumes/")
    }

    /// Registers the keep-alive agent once per installation and moves existing users off the old login item.
    static func enableOnceIfInstalled() {
        let defaults = UserDefaults.standard
        guard installed, let plan = StartupPolicy.migration(loginItem: SMAppService.mainApp.status,
                                                            attempted: defaults.bool(forKey: attemptedKey),
                                                            migrated: defaults.bool(forKey: migratedKey)) else { return }
        // One attempt only: never re-enable after the user turns Wand off in System Settings.
        defaults.set(true, forKey: attemptedKey); defaults.set(true, forKey: migratedKey)
        if plan.unregisterLoginItem { try? SMAppService.mainApp.unregister() }
        if plan.registerAgent, agent.status == .notRegistered { try? agent.register() }
    }

    static func setEnabled(_ enabled: Bool) async throws {
        UserDefaults.standard.set(true, forKey: attemptedKey)
        if enabled {
            if SMAppService.mainApp.status != .notRegistered { try? await SMAppService.mainApp.unregister() }
            // launchd starts the keep-alive copy right away; it replaces this one if this one was opened by hand.
            if agent.status != .enabled { try agent.register() }
        } else {
            // Removing the job can stop the copy launchd started. Hand this session to a plain copy first,
            // so turning the setting off does not close Wand in the user's face.
            if managedByLaunchd { try await handOff() }
            try await agent.unregister()
        }
    }

    private static func handOff() async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = false
        configuration.environment = [StartupPolicy.handoffEnvironmentKey: String(ProcessInfo.processInfo.processIdentifier)]
        _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
    }

    static var enabled: Bool { agent.status == .enabled }
    static var message: String { StartupPolicy.message(for: agent.status) }
    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
