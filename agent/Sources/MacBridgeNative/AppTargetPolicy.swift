import Foundation
import MacBridgeCore

/// Apply at execution as well as discovery: callers can supply their own bundle ID.
public enum AppTargetPolicy {
    public static func allows(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard !path.hasPrefix("/System/Library/"), !path.hasPrefix("/usr/"),
              !path.hasPrefix("/Library/Apple/"), !path.contains(".app/Contents/") else { return false }
        guard let bundle = Bundle(url: url), bundle.bundleIdentifier != nil else { return false }
        return bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool != true
            && bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool != true
    }
    public static func check(_ url: URL) throws {
        guard allows(url) else { throw ContractError(code: "protected_app") }
    }
}
