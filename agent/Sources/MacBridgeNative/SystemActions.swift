import AppKit
@preconcurrency import ApplicationServices
import IOKit.pwr_mgt
import MacBridgeCore

/// Fixed native operations. No user-provided script, executable or key sequence.
@MainActor public enum SystemActions {
    static func value(_ e: AXUIElement, _ key: String) -> CFTypeRef? {
        var v: CFTypeRef?; guard AXUIElementCopyAttributeValue(e,key as CFString,&v) == .success else { return nil }; return v
    }
    static func text(_ e: AXUIElement, _ key: String) -> String { value(e,key) as? String ?? "" }
    static func children(_ e: AXUIElement) -> [AXUIElement] { value(e,kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    static func descendants(_ root: AXUIElement, limit: Int = 600) -> [AXUIElement] {
        var queue=[root], result:[AXUIElement]=[]; let end=Date().addingTimeInterval(2)
        while !queue.isEmpty && result.count<limit && Date()<end {
            let e=queue.removeFirst(); result.append(e)
            if text(e,kAXRoleAttribute) != "AXWebArea" { queue += children(e) }
        }; return result
    }
    static func check() throws {
        guard LockStateReader.read() == .unlocked else { throw ContractError(code:"device_locked") }
        guard AXIsProcessTrusted() else { throw ContractError(code:"accessibility_permission_required") }
    }
    static func press(_ e: AXUIElement) throws {
        try check(); guard AXUIElementPerformAction(e,kAXPressAction as CFString) == .success else { throw ContractError(code:"native_control_unavailable") }
    }
    public static func lock() async throws -> JSON {
        try check()
        // Apple's standard Lock Screen shortcut, independent of removed CGSession binary.
        guard let down=CGEvent(keyboardEventSource:nil,virtualKey:12,keyDown:true),let up=CGEvent(keyboardEventSource:nil,virtualKey:12,keyDown:false) else { throw ContractError(code:"action_failed") }
        down.flags=[.maskControl,.maskCommand]; up.flags=[.maskControl,.maskCommand]
        down.post(tap:.cghidEventTap); up.post(tap:.cghidEventTap)
        for _ in 0..<30 {
            if LockStateReader.read() == .locked { return .object(["screen_locked":.bool(true)]) }
            try await Task.sleep(for:.milliseconds(100))
        }
        throw ContractError(code:"lock_not_confirmed")
    }
    public static func sleep() throws -> JSON {
        guard LockStateReader.read() == .unlocked else { throw ContractError(code:"device_locked") }
        let connection=IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
        guard connection != 0 else { throw ContractError(code:"sleep_unavailable") }
        defer { IOServiceClose(connection) }
        guard IOPMSleepSystem(connection)==kIOReturnSuccess else { throw ContractError(code:"sleep_request_denied") }
        // The network may suspend before this response arrives. This is a request acknowledgement.
        return .object(["sleep_requested":.bool(true)])
    }
    public static func focus(_ enabled: Bool) async throws -> JSON {
        try check()
        guard let app=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.controlcenter").first else { throw ContractError(code:"focus_control_unavailable") }
        let root=AXUIElementCreateApplication(app.processIdentifier); AXUIElementSetMessagingTimeout(root,0.2)
        var roots=[root]
        for key in [kAXMenuBarAttribute,"AXExtrasMenuBar"] { if let v=value(root,key),CFGetTypeID(v)==AXUIElementGetTypeID() { roots.append(v as! AXUIElement) } }
        let menu=roots.flatMap { descendants($0) }.first { text($0,kAXIdentifierAttribute)=="com.apple.menuextra.controlcenter" || text($0,kAXDescriptionAttribute)=="Control Center" }
        guard let menu else { throw ContractError(code:"focus_control_unavailable") }
        try press(menu)
        for _ in 0..<15 {
            let nodes=descendants(root)
            if let dnd=nodes.first(where:{ text($0,kAXRoleAttribute)=="AXCheckBox" && (text($0,kAXTitleAttribute)=="Do Not Disturb" || text($0,kAXDescriptionAttribute).hasPrefix("Do Not Disturb")) }),let number=value(dnd,kAXValueAttribute) as? NSNumber {
                if number.boolValue != enabled { try press(dnd) }
                for _ in 0..<10 {
                    if let current=value(dnd,kAXValueAttribute) as? NSNumber,current.boolValue==enabled { return .object(["enabled":.bool(enabled)]) }
                    try await Task.sleep(for:.milliseconds(100))
                }
                throw ContractError(code:"focus_change_not_confirmed")
            }
            if let focus=nodes.first(where:{ ["AXButton","AXCheckBox"].contains(text($0,kAXRoleAttribute)) && (text($0,kAXTitleAttribute)=="Focus" || text($0,kAXDescriptionAttribute)=="Focus") }) { try press(focus) }
            try await Task.sleep(for:.milliseconds(150))
        }
        throw ContractError(code:"focus_control_unavailable")
    }
    public static func safariCleanup(keepPinned: Bool) async throws -> JSON {
        try check()
        guard let app=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.Safari").first else { return .object(["closed_tabs":.number(0)]) }
        let root=AXUIElementCreateApplication(app.processIdentifier); AXUIElementSetMessagingTimeout(root,0.2)
        let windows=value(root,kAXWindowsAttribute) as? [AXUIElement] ?? []
        var targets:[(AXUIElement,String)]=[]
        // Preflight every tab before closing any. Never read URLs or page content.
        for window in windows {
            let tabs=descendants(window).filter { text($0,kAXIdentifierAttribute).hasPrefix("TabBarTab?") }
            if tabs.isEmpty { throw ContractError(code:"browser_tab_layout_unavailable") }
            for tab in tabs {
                let identifier=text(tab,kAXIdentifierAttribute)
                guard let pinned=pinnedState(identifier) else { throw ContractError(code:"pinned_tab_detection_unverified") }
                if keepPinned && pinned { continue }
                var actions:CFArray?; AXUIElementCopyActionNames(tab,&actions)
                let close=(actions as? [String] ?? []).first { name in
                    var description:CFString?; AXUIElementCopyActionDescription(tab,name as CFString,&description)
                    return name=="AXClose" || (description as String?)?.lowercased()=="close tab"
                }
                guard let close else { throw ContractError(code:"browser_tab_close_unavailable") }
                targets.append((tab,close))
            }
        }
        for (tab,action) in targets.reversed() {
            try check()
            guard AXUIElementPerformAction(tab,action as CFString) == .success else { throw ContractError(code:"browser_cleanup_partial") }
            try await Task.sleep(for:.milliseconds(80))
        }
        for _ in 0..<10 {
            let remaining=(value(root,kAXWindowsAttribute) as? [AXUIElement] ?? []).flatMap { descendants($0) }.filter { text($0,kAXIdentifierAttribute).hasPrefix("TabBarTab?") && (!keepPinned || pinnedState(text($0,kAXIdentifierAttribute)) == false) }
            if !remaining.contains(where: { current in targets.contains(where: { CFEqual(current,$0.0) }) }) { return .object(["closed_tabs":.number(Double(targets.count)),"kept_pinned":.bool(keepPinned)]) }
            try await Task.sleep(for:.milliseconds(100))
        }
        throw ContractError(code:"browser_cleanup_pending_user_attention")
    }
    public static func pinnedState(_ identifier:String) -> Bool? {
        guard identifier.hasPrefix("TabBarTab?") else { return nil }
        let fields=identifier.dropFirst("TabBarTab?".count).split(separator:"&").filter { $0.hasPrefix("isPinned=") }
        guard fields.count==1 else { return nil }
        switch fields[0] { case "isPinned=true":return true; case "isPinned=false":return false; default:return nil }
    }
}
