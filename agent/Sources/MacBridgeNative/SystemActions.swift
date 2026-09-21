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
    static func scan(_ root: AXUIElement, limit: Int = 600) -> (nodes: [AXUIElement], complete: Bool) {
        var queue=[root], result:[AXUIElement]=[]; let end=Date().addingTimeInterval(2)
        while !queue.isEmpty && result.count<limit && Date()<end {
            let e=queue.removeFirst(); result.append(e)
            if text(e,kAXRoleAttribute) != "AXWebArea" { queue += children(e) }
        }; return (result, queue.isEmpty)
    }
    static func descendants(_ root: AXUIElement) -> [AXUIElement] { scan(root).nodes }
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
        return .object([:])
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
                    if let current=value(dnd,kAXValueAttribute) as? NSNumber,current.boolValue==enabled { return .object([:]) }
                    try await Task.sleep(for:.milliseconds(100))
                }
                throw ContractError(code:"focus_change_not_confirmed")
            }
            if let focus=nodes.first(where:{ text($0,kAXRoleAttribute)=="AXButton" && (text($0,kAXTitleAttribute)=="Focus" || text($0,kAXDescriptionAttribute)=="Focus") }) { try press(focus) }
            try await Task.sleep(for:.milliseconds(150))
        }
        throw ContractError(code:"focus_control_unavailable")
    }
    public static func chromeCleanup(keepPinned: Bool) async throws -> JSON {
        try check()
        guard let app=NSRunningApplication.runningApplications(withBundleIdentifier:"com.google.Chrome").first else { return .object([:]) }
        let root=AXUIElementCreateApplication(app.processIdentifier); AXUIElementSetMessagingTimeout(root,0.2)
        let windows=value(root,kAXWindowsAttribute) as? [AXUIElement] ?? []
        guard windows.count<=10 else { throw ContractError(code:"browser_cleanup_limit_exceeded") }
        guard let bar=value(root,kAXMenuBarAttribute),CFGetTypeID(bar)==AXUIElementGetTypeID() else { throw ContractError(code:"browser_menu_unavailable") }
        let menuBar=bar as! AXUIElement
        func menuItem(_ menu:String,_ title:String) throws -> AXUIElement {
            guard let top=children(menuBar).first(where:{text($0,kAXTitleAttribute)==menu}) else { throw ContractError(code:"browser_menu_unavailable") }
            try press(top)
            guard let item=descendants(top).first(where:{text($0,kAXRoleAttribute)=="AXMenuItem" && text($0,kAXTitleAttribute)==title}) else { throw ContractError(code:"browser_menu_unavailable") }
            return item
        }
        func tabs(_ window:AXUIElement) throws -> [AXUIElement] {
            let tree=scan(window); guard tree.complete else { throw ContractError(code:"browser_cleanup_limit_exceeded") }
            return tree.nodes.filter { ["AXRadioButton","AXTab"].contains(text($0,kAXRoleAttribute)) }
        }
        for window in windows {
            try check()
            guard text(window,kAXSubroleAttribute)=="AXStandardWindow",!children(window).contains(where:{text($0,kAXRoleAttribute)=="AXSheet"}) else { throw ContractError(code:"browser_cleanup_pending_user_attention") }
            app.activate()
            guard AXUIElementPerformAction(window,kAXRaiseAction as CFString) == .success else { throw ContractError(code:"browser_window_unavailable") }
            if !keepPinned {
                guard let v=value(window,kAXCloseButtonAttribute),CFGetTypeID(v)==AXUIElementGetTypeID() else { throw ContractError(code:"browser_window_unavailable") }
                try press(v as! AXUIElement)
                continue
            }
            let before=try tabs(window)
            guard let newTab=descendants(window).first(where:{text($0,kAXRoleAttribute)=="AXButton" && text($0,kAXTitleAttribute)=="New Tab"}) else { throw ContractError(code:"browser_tab_layout_unavailable") }
            try press(newTab); try await Task.sleep(for:.milliseconds(200))
            let added=try tabs(window).filter { candidate in !before.contains(where:{CFEqual(candidate,$0)}) }
            guard added.count==1,let temporary=added.first,(value(temporary,kAXValueAttribute) as? NSNumber)?.boolValue==true else { throw ContractError(code:"browser_tabs_changed") }
            let closeOthers=try menuItem("Tab","Close Other Tabs")
            if (value(closeOthers,kAXEnabledAttribute) as? NSNumber)?.boolValue == true { try press(closeOthers) }
            else { _=AXUIElementPerformAction(menuBar,kAXCancelAction as CFString) }
            try await Task.sleep(for:.milliseconds(150))
            let remainingClose=try menuItem("Tab","Close Other Tabs")
            guard (value(remainingClose,kAXEnabledAttribute) as? NSNumber)?.boolValue == false else { throw ContractError(code:"browser_cleanup_pending_user_attention") }
            guard (value(temporary,kAXValueAttribute) as? NSNumber)?.boolValue==true,
                  !children(window).contains(where:{text($0,kAXRoleAttribute)=="AXSheet"}) else { throw ContractError(code:"browser_cleanup_pending_user_attention") }
            try press(menuItem("File","Close Tab"))
            try await Task.sleep(for:.milliseconds(150))
            guard !(try tabs(window)).contains(where:{CFEqual($0,temporary)}) else { throw ContractError(code:"browser_cleanup_pending_user_attention") }
        }
        if !keepPinned {
            let remaining=value(root,kAXWindowsAttribute) as? [AXUIElement] ?? []
            guard !remaining.contains(where:{ current in windows.contains(where:{CFEqual(current,$0)}) }) else { throw ContractError(code:"browser_cleanup_pending_user_attention") }
        }
        return .object([:])
    }
    public static func safariCleanup(keepPinned: Bool) async throws -> JSON {
        try check()
        guard let app=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.Safari").first else { return .object([:]) }
        let root=AXUIElementCreateApplication(app.processIdentifier); AXUIElementSetMessagingTimeout(root,0.2)
        let windows=value(root,kAXWindowsAttribute) as? [AXUIElement] ?? []
        guard windows.count <= 20 else { throw ContractError(code:"browser_cleanup_limit_exceeded") }
        guard windows.allSatisfy({ text($0,kAXSubroleAttribute)=="AXStandardWindow" && !children($0).contains(where:{ text($0,kAXRoleAttribute)=="AXSheet" }) }) else { throw ContractError(code:"browser_cleanup_pending_user_attention") }
        if !keepPinned {
            let buttons=windows.compactMap { window -> AXUIElement? in
                guard let v=value(window,kAXCloseButtonAttribute), CFGetTypeID(v)==AXUIElementGetTypeID() else { return nil }
                return (v as! AXUIElement)
            }
            guard buttons.count==windows.count else { throw ContractError(code:"browser_tab_close_unavailable") }
            for button in buttons { try press(button); try await Task.sleep(for:.milliseconds(100)) }
            for _ in 0..<10 {
                let remaining=value(root,kAXWindowsAttribute) as? [AXUIElement] ?? []
                if !remaining.contains(where:{ current in windows.contains(where:{CFEqual(current,$0)}) }) {
                    return .object([:])
                }
                try await Task.sleep(for:.milliseconds(100))
            }
            throw ContractError(code:"browser_cleanup_pending_user_attention")
        }
        var targets:[(AXUIElement,String)]=[]
        // Preflight every tab before closing any. Never read URLs or page content.
        for window in windows {
            let traversal=scan(window)
            let controls=traversal.nodes
            // The traversal must be complete before any destructive input is sent.
            guard traversal.complete else { throw ContractError(code:"browser_cleanup_limit_exceeded") }
            let tabs=controls.filter { text($0,kAXIdentifierAttribute).hasPrefix("TabBarTab?") }
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
        guard targets.count <= 80 else { throw ContractError(code:"browser_cleanup_limit_exceeded") }
        for (tab,action) in targets.reversed() {
            try check()
            guard pinnedState(text(tab,kAXIdentifierAttribute)) == false else { throw ContractError(code:"browser_tabs_changed") }
            guard AXUIElementPerformAction(tab,action as CFString) == .success else { throw ContractError(code:"browser_cleanup_partial") }
            try await Task.sleep(for:.milliseconds(80))
        }
        for _ in 0..<10 {
            let remaining=(value(root,kAXWindowsAttribute) as? [AXUIElement] ?? []).flatMap { descendants($0) }.filter { text($0,kAXIdentifierAttribute).hasPrefix("TabBarTab?") && (!keepPinned || pinnedState(text($0,kAXIdentifierAttribute)) == false) }
            if !remaining.contains(where: { current in targets.contains(where: { CFEqual(current,$0.0) }) }) { return .object([:]) }
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
