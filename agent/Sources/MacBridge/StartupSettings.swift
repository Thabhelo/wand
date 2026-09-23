import Foundation
import ServiceManagement

@MainActor enum StartupSettings {
    private static let attemptedKey = "wand-login-registration-attempted"

    static func enableOnceIfInstalled() {
        guard !UserDefaults.standard.bool(forKey: attemptedKey),
              Bundle.main.bundleURL.pathExtension == "app",
              !Bundle.main.bundleURL.path.contains("/AppTranslocation/"),
              !Bundle.main.bundleURL.path.hasPrefix("/Volumes/") else { return }
        // Do not re-enable this after the user disables it in System Settings.
        UserDefaults.standard.set(true, forKey: attemptedKey)
        if SMAppService.mainApp.status == .notRegistered { try? SMAppService.mainApp.register() }
    }

    static func setEnabled(_ enabled: Bool) throws {
        UserDefaults.standard.set(true, forKey: attemptedKey)
        if enabled {
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static var enabled: Bool { SMAppService.mainApp.status == .enabled }
    static var message: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "Starts quietly in the menu bar when you log in."
        case .requiresApproval: return "Allow Wand in System Settings → General → Login Items."
        case .notRegistered: return "Off. Open Wand yourself after logging in."
        case .notFound: return "Move Wand to Applications, then enable this setting."
        @unknown default: return "Check Wand in System Settings → General → Login Items."
        }
    }
    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
