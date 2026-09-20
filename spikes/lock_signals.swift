import Foundation
import CoreGraphics
import IOKit
let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
let root = IORegistryGetRootEntry(kIOMainPortDefault)
defer { IOObjectRelease(root) }
let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [[String: Any]] ?? []
func flags(_ d: [String:Any]) -> [String:Any] {
    var result: [String:Any] = [:]
    for k in ["kCGSSessionScreenIsLocked", "CGSSessionScreenIsLocked", "kCGSSessionOnConsoleKey", "kCGSSessionLoginDoneKey", "kCGSSessionSecureInputPID"] {
        if let b = d[k] as? NSNumber { result[k] = b }
    }
    result["matches_current_uid"] = (d["kCGSSessionUserIDKey"] as? NSNumber)?.uint32Value == getuid()
    return result
}
let out: [String:Any] = ["cg_session":flags(session), "console_sessions":users.map(flags)]
print(String(data: try JSONSerialization.data(withJSONObject: out, options:.sortedKeys), encoding:.utf8)!)
