import AppKit
import ApplicationServices
import CoreGraphics
import MacBridgeCore

/// Build support is separate from live permissions; checking never requests access.
@MainActor public enum DeviceCapabilityReport {
    public static let actions: [String] = ["lock_screen", "sleep_mac", "media_play_pause", "media_next", "media_previous", "set_volume", "mute", "unmute", "close_browser_tabs", "quit_app", "open_app", "open_url", "run_shortcut", "toggle_do_not_disturb", "list_apps", "get_state", "desktop_observe", "desktop_act", "desktop_stop"]
    public static let features = ["audio_output_state", "playback_state", "app_inventory", "desktop_images", "system_status"]
    public static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development" }
    public static func read(desktopEnabled: Bool) -> JSON {
        let unlocked = LockStateReader.read() == .unlocked
        func permission(_ granted: @autoclosure () -> Bool) -> JSON {
            unlocked ? .string(granted() ? "granted" : "denied") : .string("unknown")
        }
        return .object([
            "schema_version": .number(1), "agent_version": .string(version),
            "agent_build": (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String).map(JSON.string) ?? .null,
            "actions": .array(actions.map(JSON.string)), "features": .array(features.map(JSON.string)),
            "permissions": .object([
                "desktop_control": permission(desktopEnabled),
                "accessibility": permission(AXIsProcessTrusted()),
                "screen_recording": permission(CGPreflightScreenCaptureAccess())
            ])
        ])
    }
}
