import AppKit
import Carbon
import MacBridgeCore

@MainActor public enum NowPlayingReader {
    public static func normalized(title: String?, artist: String?, source: String) -> JSON {
        guard ["Music", "Spotify"].contains(source), let title, !title.isEmpty,
              let artist, !artist.isEmpty else { return .null }
        return .object(["title": .string(String(title.prefix(500))),
                        "artist": .string(String(artist.prefix(500))), "source_app": .string(source)])
    }
    /// Read only already-running, already-authorized apps. A state request never
    /// launches a media app or opens an Automation permission prompt.
    public static func read() async -> JSON {
        for (bundle, name) in [("com.apple.Music", "Music"), ("com.spotify.client", "Spotify")] {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty else { continue }
            let permitted = await Task.detached {
                guard let address = NSAppleEventDescriptor(descriptorType: typeApplicationBundleID, data: Data(bundle.utf8)) else { return false }
                return AEDeterminePermissionToAutomateTarget(address.aeDesc, typeWildCard, typeWildCard, false) == noErr
            }.value
            guard permitted else { continue }
            let source = """
            with timeout of 1 seconds
                tell application id "\(bundle)"
                    if player state is not playing then return {}
                    return {name of current track, artist of current track}
                end tell
            end timeout
            """
            var error: NSDictionary?
            guard let script = NSAppleScript(source: source) else { continue }
            let result = script.executeAndReturnError(&error)
            guard error == nil, result.numberOfItems == 2 else { continue }
            let state = normalized(title: result.atIndex(1)?.stringValue, artist: result.atIndex(2)?.stringValue, source: name)
            if state != .null { return state }
        }
        return .null
    }
}
