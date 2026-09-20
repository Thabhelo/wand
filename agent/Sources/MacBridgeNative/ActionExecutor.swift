import AppKit
import Foundation
import IOKit.ps
import MacBridgeCore

/// Native implementation boundary. Caller must validate the shared contract, reserve the
/// command ID and check current session + lock state immediately before invoking this.
@MainActor public final class ActionExecutor {
    public init() {}
    public func executeGuarded(action: String, params: JSON, shortcuts: [String]) async throws -> JSON {
        if let guarded = try CommandGate.lockedResult(action: action, locked: LockStateReader.read().locked) { return guarded }
        let result = try await execute(action: action, params: params, shortcuts: shortcuts)
        if action == "get_state", let guarded = try CommandGate.lockedResult(action: action, locked: LockStateReader.read().locked) { return guarded }
        return result
    }
    public func execute(action: String, params: JSON, shortcuts: [String]) async throws -> JSON {
        switch action {
        case "open_url":
            guard let text = params["url"]?.string, let url = URL(string: text), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { throw ContractError(code: "invalid_url") }
            guard NSWorkspace.shared.open(url) else { throw ContractError(code: "action_failed") }
        case "open_app":
            let url = try applicationURL(params)
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        case "quit_app":
            let url = try applicationURL(params)
            guard let id = Bundle(url: url)?.bundleIdentifier else { throw ContractError(code: "app_not_found") }
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            guard !apps.isEmpty else { return .object([:]) }
            guard apps.allSatisfy({ $0.terminate() }) else { throw ContractError(code: "quit_refused") }
            // terminate() only requests quit; never claim success if a save dialog keeps it alive.
            for _ in 0..<20 {
                if apps.allSatisfy({ $0.isTerminated }) { return .object([:]) }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw ContractError(code: "quit_pending_user_attention")
        case "run_shortcut":
            guard let name = params["name"]?.string, ShortcutAllowlist(names: shortcuts).allows(name) else { throw ContractError(code: "action_not_allowlisted") }
            // The option terminator was verified with a nonexistent leading-hyphen name.
            // A Shortcut name is always an operand, never a CLI option or shell fragment.
            try await process("/usr/bin/shortcuts", arguments: ["run", "--", name])
        case "set_volume":
            guard let level = params["level"]?.number, level >= 0, level <= 100, level.rounded() == level else { throw ContractError(code: "invalid_params") }
            try appleScript("set volume output volume " + String(Int(level)))
        case "mute": try appleScript("set volume with output muted")
        case "unmute": try appleScript("set volume without output muted")
        case "media_play_pause", "media_next", "media_previous":
            let supported = [("com.apple.Music", "Music"), ("com.spotify.client", "Spotify")]
            guard let app = supported.first(where: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.0).isEmpty }) else { throw ContractError(code: "media_app_not_running") }
            let verb = action == "media_play_pause" ? "playpause" : action == "media_next" ? "next track" : "previous track"
            // All script fragments are closed constants. No user strings enter AppleScript.
            try explainAutomation(app.1)
            try appleScript("tell application id \"" + app.0 + "\" to " + verb)
        case "get_state":
            let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.localizedName).map { String($0.prefix(160)) }.filter { !$0.isEmpty }.prefix(512)
            var battery: JSON = .null
            if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
                for source in sources {
                    if let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any], let capacity = values[kIOPSCurrentCapacityKey] as? Int, let max = values[kIOPSMaxCapacityKey] as? Int, max > 0 {
                        battery = .object(["percent": .number(min(100, Swift.max(0, (Double(capacity) / Double(max) * 100).rounded()))), "charging": .bool(values[kIOPSIsChargingKey] as? Bool ?? false)])
                    }
                }
            }
            return .object(["screen_locked": .bool(false), "frontmost_app": NSWorkspace.shared.frontmostApplication?.localizedName.map { JSON.string(String($0.prefix(160))) } ?? .null,
                            "now_playing": .null, "battery": battery, "running_apps": .array(apps.map(JSON.string))])
        case "lock_screen": throw ContractError(code: "lock_api_unverified")
        case "close_browser_tabs": throw ContractError(code: "pinned_tab_detection_unverified")
        case "toggle_do_not_disturb": throw ContractError(code: "focus_api_unverified")
        case "sleep_mac": throw ContractError(code: "sleep_wake_verification_required")
        default: throw ContractError(code: "action_unsupported")
        }
        return .object([:])
    }
    private func applicationURL(_ params: JSON) throws -> URL {
        if let id = params["bundle_id"]?.string, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return url }
        if let name = params["app_name"]?.string {
            // Resolve only installed application bundles; names cannot become paths or scripts.
            let matches = ["/Applications", "/System/Applications", "/System/Applications/Utilities"].flatMap { folder -> [URL] in
                (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil)) ?? []
            }.filter { $0.pathExtension == "app" && $0.deletingPathExtension().lastPathComponent == name }
            if matches.count == 1 { return matches[0] }
        }
        throw ContractError(code: "app_not_found_or_ambiguous")
    }
    private func explainAutomation(_ name: String) throws {
        let key = "automation-explained-" + name
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let alert = NSAlert(); alert.messageText = "Allow Wand to control " + name + "?"
        alert.informativeText = "Wand needs Automation permission to change playback. macOS may show its permission dialog next."
        alert.addButton(withTitle: "Continue"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { throw ContractError(code: "permission_required") }
        UserDefaults.standard.set(true, forKey: key)
    }
    private func appleScript(_ source: String) throws {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw ContractError(code: "action_failed") }
        _ = script.executeAndReturnError(&error)
        if error != nil { throw ContractError(code: "automation_failed_or_permission_required") }
    }
    private func process(_ path: String, arguments: [String]) async throws {
        let task = Process(); task.executableURL = URL(fileURLWithPath: path); task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
        try task.run()
        for _ in 0..<120 {
            if !task.isRunning {
                guard task.terminationStatus == 0 else { throw ContractError(code: "action_failed") }
                return
            }
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { task.terminate(); throw error }
        }
        task.terminate(); throw ContractError(code: "action_timeout_outcome_unknown")
    }
}
