import Foundation
import CoreGraphics
import CoreFoundation
import IOKit

public enum ScreenState: String, Sendable {
    case unlocked, locked, inactive, unknown
    public var locked: Bool? {
        switch self { case .unlocked: return false; case .locked: return true; default: return nil }
    }
}

/// IOConsoleLocked is an observed OS implementation property, not an Apple-supported
/// API contract. Require an explicit CFBoolean, matching active UID in BOTH sources,
/// and exactly one console session. Never interpret absence or numeric zero as unlocked.
public enum LockStateReader {
    public static func explicitBoolean(_ value: Any?) -> Bool? {
        guard let value, CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() else { return nil }
        return (value as! NSNumber).boolValue
    }
    public static func evaluate(root: [String: Any], session: [String: Any]?, uid: UInt32) -> ScreenState {
        guard let session,
              let current = session["kCGSSessionUserIDKey"] as? NSNumber,
              current.uint32Value == uid,
              let ownConsole = explicitBoolean(session["kCGSSessionOnConsoleKey"]),
              let sessions = root["IOConsoleUsers"] as? [[String: Any]] else { return .unknown }
        if !ownConsole { return .inactive }
        // Malformed entries are not silently filtered out.
        guard sessions.allSatisfy({ explicitBoolean($0["kCGSSessionOnConsoleKey"]) != nil }) else { return .unknown }
        let active = sessions.filter { explicitBoolean($0["kCGSSessionOnConsoleKey"]) == true }
        guard active.count == 1, let activeUID = active[0]["kCGSSessionUserIDKey"] as? NSNumber,
              activeUID.uint32Value == uid else { return .unknown }
        guard let locked = explicitBoolean(root["IOConsoleLocked"]) else { return .unknown }
        if let perSession = active[0]["CGSSessionScreenIsLocked"] {
            guard let specific = explicitBoolean(perSession), specific == locked else { return .unknown }
        }
        return locked ? .locked : .unlocked
    }
    public static func read() -> ScreenState {
        let entry = IORegistryGetRootEntry(kIOMainPortDefault)
        guard entry != 0 else { return .unknown }
        defer { IOObjectRelease(entry) }
        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        guard let users = property("IOConsoleUsers"), let locked = property("IOConsoleLocked") else { return .unknown }
        let root: [String: Any] = ["IOConsoleUsers": users, "IOConsoleLocked": locked]
        return evaluate(root: root, session: CGSessionCopyCurrentDictionary() as? [String: Any], uid: getuid())
    }
}
