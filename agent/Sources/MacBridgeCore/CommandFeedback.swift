import Foundation

/// Presentation only. Protocol responses and the private audit log keep their stable codes.
public enum CommandFeedback {
    public static func actionName(_ action: String) -> String {
        let names = [
            "lock_screen": "Lock Mac", "sleep_mac": "Sleep Mac",
            "media_play_pause": "Play or pause", "media_next": "Next track", "media_previous": "Previous track",
            "set_volume": "Change volume", "mute": "Mute", "unmute": "Unmute",
            "close_browser_tabs": "Close browser tabs", "quit_app": "Close app", "open_app": "Open app",
            "open_url": "Open website", "run_shortcut": "Run Shortcut", "toggle_do_not_disturb": "Change Focus",
            "list_apps": "List apps", "get_state": "Check Mac status", "desktop_observe": "Look at app",
            "desktop_act": "Use app", "desktop_stop": "Pause desktop control"
        ]
        return names[action] ?? "Mac action"
    }

    public static func error(_ code: String) -> String {
        switch code {
        case "accessibility_permission_required":
            return "macOS isn’t allowing Wand to control apps. Check Wand in System Settings → Privacy & Security → Accessibility."
        case "screen_recording_permission_required":
            return "Allow Screen Recording for Wand in System Settings, or turn off images."
        case "desktop_permission_required", "desktop_app_not_allowed":
            return "Enable desktop control in Wand’s Connection settings."
        case "desktop_app_not_running": return "Open this app first, then look again."
        case "desktop_window_unavailable": return "Open a window in this app, then look again."
        case "desktop_snapshot_expired": return "This view expired. Look at the app again."
        case "desktop_focus_changed", "desktop_capture_window_mismatch":
            return "The app or window changed. Look at it again before continuing."
        case "desktop_target_unavailable": return "That control is no longer available. Look at the app again."
        case "desktop_protected_ui", "desktop_app_excluded":
            return "This is a protected screen. Complete this step directly on your Mac."
        case "desktop_target_not_editable": return "Wand can’t type into this field. Choose another field."
        case "desktop_action_failed": return "The app didn’t accept that action. Look at it again before retrying."
        case "desktop_busy": return "Wand is still reading the app. Wait a moment, then try again."
        case "desktop_capture_failed": return "Wand couldn’t capture this window. Look again, or turn off images."
        case "desktop_image_required": return "Look at the app with images turned on before clicking."
        case "desktop_image_too_large": return "This window is too large to capture. Make it smaller or turn off images."
        case "desktop_observation_too_large": return "This window has too much content. Try a smaller window."
        case "invalid_params", "invalid_message": return "Check the action’s details, then try again."
        case "invalid_url": return "Enter a complete website address beginning with https:// or http://."
        case "protected_app": return "This is a macOS component. Wand cannot open or close it."
        case "app_not_found", "app_not_found_or_ambiguous": return "App not found. Refresh the app list and choose it again."
        case "device_locked": return "Unlock this Mac before running this action."
        case "lock_state_unknown", "session_changed": return "This Mac’s session changed. Return to it before trying again."
        case "media_app_not_running": return "Open Music or Spotify first, then try playback again."
        case "automation_failed_or_permission_required":
            return "The app didn’t respond. Check Wand’s Automation access in System Settings → Privacy & Security."
        case "permission_required": return "Permission wasn’t granted. Try again when you’re ready to allow it."
        case "action_not_allowlisted": return "Add this exact name to Wand’s approved Shortcuts first."
        case "invalid_shortcut_name": return "Enter the Shortcut’s exact name without line breaks."
        case "quit_pending_user_attention": return "The app is still open. Check it for a save dialog."
        case "quit_refused": return "The app declined to close. Check it on your Mac."
        case "action_timeout_outcome_unknown": return "This took too long. Check the Mac before retrying; the result is unknown."
        case "command_expired", "invalid_deadline": return "This request expired before it could run. Send it again."
        case "duplicate_command": return "This request was already received. Check its result before trying again."
        case "action_unsupported": return "This version of Wand doesn’t support that action. Check for an update."
        case "lock_not_confirmed": return "Wand couldn’t confirm the Mac locked. Check the Mac before retrying."
        case "sleep_unavailable", "sleep_request_denied": return "macOS didn’t accept the sleep request. Try again on the Mac."
        case "focus_control_unavailable", "native_control_unavailable": return "Wand couldn’t reach this control. Check it on the Mac."
        case "focus_change_not_confirmed": return "Wand couldn’t confirm the Focus change. Check Control Center."
        case "pinned_tab_detection_unverified": return "Wand can’t identify pinned tabs in this window, so it left them open."
        case "browser_tabs_changed": return "The browser tabs changed. Check what’s open before trying again."
        case "browser_cleanup_partial": return "Some tabs may have closed. Check the browser before trying again."
        case "browser_cleanup_pending_user_attention": return "The browser is waiting for you. Check for a save or confirmation dialog."
        case "browser_cleanup_limit_exceeded": return "There are too many tabs to handle at once. Close some, then try again."
        case "browser_menu_unavailable", "browser_tab_close_unavailable", "browser_tab_layout_unavailable", "browser_window_unavailable":
            return "Wand couldn’t reach the browser’s tab controls. Check its windows before trying again."
        case "device_offline", "relay_request_failed": return "Wand lost its connection. Check your internet connection and try again."
        case "device_token_revoked", "device_identity_mismatch": return "This Mac’s connection is no longer valid. Connect it again."
        case "pairing_expired": return "This setup link expired. Click Connect to start again."
        case "pairing_pending": return "Approve this Mac in your browser to finish connecting."
        case "https_relay_required", "invalid_dashboard": return "Enter a valid HTTPS service address in Connection settings."
        case "keychain_read_failed", "keychain_write_failed", "keychain_delete_failed", "keychain_credentials_invalid", "connection_or_storage_failed":
            return "Wand couldn’t access its connection keys. Check Connection settings and any Keychain prompt."
        case "invalid_local_log": return "Wand couldn’t read or save its activity log. Check this Mac before trying again."
        default:
            // Unknown codes can come from newer peers. Never present arbitrary server text as UI copy.
            return "Wand couldn’t complete this action. Check the Mac before trying again."
        }
    }

    public static func success(action: String, result: JSON) -> String {
        switch action {
        case "open_app":
            if result["already_open"] == .bool(true) {
                return result["focused"] == .bool(true) ? "App already open · brought to front" : "App was already open"
            }
            return "App opened"
        case "quit_app": return result["already_closed"] == .bool(true) ? "App was already closed" : "App closed"
        case "lock_screen": return result["already_locked"] == .bool(true) ? "Mac was already locked" : "Mac locked"
        case "get_state": return result["screen_locked"] == .bool(true) ? "Mac is locked" : "Mac status updated"
        case "desktop_observe": return "App view updated"
        case "desktop_act": return "Interaction sent"
        case "desktop_stop": return "Desktop control paused"
        case "list_apps": return "App list updated"
        case "open_url": return "Website opened"
        case "mute": return "Audio muted"
        case "unmute": return "Audio unmuted"
        case "set_volume": return "Volume changed"
        case "run_shortcut": return "Shortcut completed"
        case "media_play_pause": return "Playback toggled"
        case "media_next": return "Skipped to next track"
        case "media_previous": return "Returned to previous track"
        case "sleep_mac": return "Sleep requested"
        case "close_browser_tabs": return "Browser tabs closed"
        case "toggle_do_not_disturb": return "Focus updated"
        default: return "Completed"
        }
    }

    public static func outcome(_ value: String) -> String {
        value == "succeeded" ? "Completed" : error(value)
    }
}
