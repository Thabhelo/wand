import AppKit
import MacBridgeCore

@MainActor enum AudioStatus {
    static func read() -> JSON {
        // Standard Additions reads the same output settings used by set_volume.
        // No app is launched and no Automation permission is requested.
        var error: NSDictionary?
        let result = NSAppleScript(source: "set settings to get volume settings\nreturn {output volume of settings, output muted of settings}")?.executeAndReturnError(&error)
        guard error == nil, let result, result.numberOfItems == 2,
              let volume = result.atIndex(1), let muted = result.atIndex(2) else { return .null }
        return .object(["volume": .number(Double(max(0, min(100, volume.int32Value)))), "muted": .bool(muted.booleanValue)])
    }
}
