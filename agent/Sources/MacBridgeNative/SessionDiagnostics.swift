import Foundation
import AppKit
import CoreGraphics
import ApplicationServices
import MacBridgeCore

public struct SessionDiagnostics: Sendable, Codable {
    public let macOS: String
    public let guiSessionAvailable: Bool
    public let sessionOnConsole: Bool?
    public let sessionLoginDone: Bool?
    public let legacyLockExecutablePresent: Bool
    public let accessibilityGranted: Bool
    public let lockState: String
    public let liveActionsEnabled: Bool
    @MainActor public static func capture() -> Self {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return Self(macOS: ProcessInfo.processInfo.operatingSystemVersionString,
                    guiSessionAvailable: session != nil,
                    sessionOnConsole: session?[kCGSessionOnConsoleKey as String] as? Bool,
                    sessionLoginDone: session?[kCGSessionLoginDoneKey as String] as? Bool,
                    legacyLockExecutablePresent: FileManager.default.isExecutableFile(atPath: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"),
                    accessibilityGranted: AXIsProcessTrusted(), lockState: "unknown_unverified", liveActionsEnabled: false)
    }
}

/// Session changes invalidate all work from previous generations. Neither a login nor
/// an active console session proves that the screen is unlocked.
public struct SessionFence: Sendable {
    public private(set) var generation: UInt64 = 0
    public private(set) var suspended = false
    public init() {}
    public mutating func suspend() { generation &+= 1; suspended = true }
    public mutating func resume() { generation &+= 1; suspended = false }
    public func accepts(_ captured: UInt64) -> Bool { !suspended && generation == captured }
}

public struct ShortcutAllowlist: Sendable {
    public private(set) var names: [String]
    public init(names: [String] = []) { self.names = names }
    public mutating func add(_ name: String) throws {
        guard !name.isEmpty, name.unicodeScalars.count <= 200,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ContractError(code: "invalid_shortcut_name")
        }
        // Deliberately no trimming, case folding or Unicode normalization.
        if !names.contains(where: { Array($0.utf8) == Array(name.utf8) }) { names.append(name) }
    }
    public mutating func remove(_ name: String) { names.removeAll { Array($0.utf8) == Array(name.utf8) } }
    public func allows(_ name: String) -> Bool { names.contains { Array($0.utf8) == Array(name.utf8) } }
}
