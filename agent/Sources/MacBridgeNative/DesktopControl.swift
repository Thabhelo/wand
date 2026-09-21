import AppKit
@preconcurrency import ApplicationServices
import ScreenCaptureKit
import MacBridgeCore

/// Muse owns planning. This executor only observes or performs one locally authorized step.
/// Desktop consent persists; observations never survive pause, lock, sleep or restart.
@MainActor public final class DesktopControl {
    public private(set) var bundleID: String?
    public private(set) var approvedApps: [String] = []
    public private(set) var deadline = Date.distantPast
    private var epoch: UInt64 = 0
    private var observing = false
    private var snapshotID: String?
    private var snapshotAt = Date.distantPast
    private var nodes: [String: AXUIElement] = [:]
    private var window: AXUIElement?
    private var pid: pid_t = 0
    private var imageSize: CGSize?
    private let defaults: UserDefaults?
    public var desktopWide: Bool { defaults?.bool(forKey: "desktop-control-consent-v1") == true }
    public init(defaults: UserDefaults? = nil) { self.defaults = defaults }
    public func enableDesktop() { suspend(); defaults?.set(true, forKey: "desktop-control-consent-v1") }
    public func suspend() { epoch &+= 1; invalidate() }
    public var active: Bool { desktopWide || (bundleID != nil && deadline > Date()) }
    public func stop() { defaults?.set(false, forKey: "desktop-control-consent-v1"); epoch &+= 1; bundleID = nil; approvedApps = []; deadline = .distantPast; invalidate() }
    private func invalidate() { snapshotID = nil; nodes.removeAll(); window = nil; imageSize = nil }
    public static func allowedBundle(_ id: String) -> Bool {
        // These are explicit exclusions, not a claim that GUI access cannot execute code.
        !["com.apple.SecurityAgent", "com.apple.loginwindow", "com.apple.keychainaccess", "com.apple.Passwords", "local.macbridge.agent"].contains(id)
    }
    public func grant(bundleID: String) throws {
        guard Self.allowedBundle(bundleID) else { throw ContractError(code: "desktop_app_excluded") }
        try grant(bundleIDs: [bundleID])
    }
    public func grant(bundleIDs: [String]) throws {
        guard !bundleIDs.isEmpty, bundleIDs.count <= 10, bundleIDs.allSatisfy(Self.allowedBundle) else { throw ContractError(code: "desktop_app_excluded") }
        stop(); approvedApps = Array(Set(bundleIDs)).sorted(); bundleID = approvedApps.first; deadline = Date().addingTimeInterval(900)
    }
    public func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    private func check(_ expected: String? = nil) throws -> NSRunningApplication {
        guard active else { throw ContractError(code: "desktop_permission_required") }
        guard let requested = expected ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? bundleID else { throw ContractError(code:"desktop_app_not_running") }
        guard Self.allowedBundle(requested) else { throw ContractError(code:"desktop_app_excluded") }
        guard desktopWide || approvedApps.contains(requested) else { throw ContractError(code: "desktop_app_not_allowed") }
        self.bundleID = requested
        guard LockStateReader.read() == .unlocked else { suspend(); throw ContractError(code: "device_locked") }
        guard AXIsProcessTrusted() else { throw ContractError(code: "accessibility_permission_required") }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: requested).first else { throw ContractError(code: "desktop_app_not_running") }
        return app
    }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private func text(_ element: AXUIElement, _ name: String) -> String { attribute(element,name) as? String ?? "" }
    private func secure(_ element: AXUIElement) -> Bool {
        text(element,kAXSubroleAttribute) == "AXSecureTextField" || text(element,kAXRoleAttribute) == "AXSecureTextField"
    }
    private func rect(_ element: AXUIElement) -> CGRect? {
        guard let p = attribute(element,kAXPositionAttribute), let s = attribute(element,kAXSizeAttribute), CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue,.cgPoint,&point), AXValueGetValue(s as! AXValue,.cgSize,&size) else { return nil }
        return CGRect(origin:point,size:size)
    }
    private func safeWindow(_ app: NSRunningApplication) throws -> AXUIElement {
        let root=AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root,0.2)
        guard let value=attribute(root,kAXFocusedWindowAttribute), CFGetTypeID(value)==AXUIElementGetTypeID() else { throw ContractError(code:"desktop_window_unavailable") }
        let w=value as! AXUIElement
        guard text(w,kAXSubroleAttribute) != "AXSystemDialog" else { throw ContractError(code:"desktop_protected_ui") }
        return w
    }
    public func observe(_ params: JSON) async throws -> JSON {
        guard !observing else { throw ContractError(code:"desktop_busy") }
        observing = true; defer { observing = false }
        let app=try check(params["bundle_id"]?.string)
        let capturedEpoch = epoch
        let observedBundle = app.bundleIdentifier ?? ""
        app.activate()
        try await Task.sleep(for:.milliseconds(150))
        guard epoch == capturedEpoch else { throw ContractError(code:"desktop_permission_required") }
        _ = try check(observedBundle)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { throw ContractError(code:"desktop_focus_changed") }
        let w=try safeWindow(app);invalidate();window=w;pid=app.processIdentifier
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var output:[JSON]=[];var queue=[w];
        if params["include_menus"] == .bool(true), let menus = attribute(root, kAXMenuBarAttribute), CFGetTypeID(menus) == AXUIElementGetTypeID() { queue.append(menus as! AXUIElement) };var visited=Set<CFHashCode>();var count=0
        let end=Date().addingTimeInterval(3)
        while !queue.isEmpty && output.count<60 && count<600 && Date()<end {
            let item=queue.removeFirst();count+=1
            guard visited.insert(CFHash(item)).inserted else { continue }
            AXUIElementSetMessagingTimeout(item,0.15)
            if secure(item) { continue }
            let role=text(item,kAXRoleAttribute)
            var names:CFArray?;_ = AXUIElementCopyActionNames(item,&names)
            var supportedActions=names as? [String] ?? []
            if ["AXScrollArea", "AXWebArea"].contains(role) {
                for action in ["AXScrollUpByPage", "AXScrollDownByPage"] where !supportedActions.contains(action) { supportedActions.append(action) }
            }
            let actions=supportedActions.prefix(12)
            let title=text(item,kAXTitleAttribute);let label=title.isEmpty ? text(item,kAXDescriptionAttribute) : title
            // Traverse layout containers without spending the returned-control budget
            // on them. Chrome and SwiftUI nest useful controls many levels deep.
            if let children=attribute(item,kAXChildrenAttribute) as? [AXUIElement] { queue.append(contentsOf:children.prefix(160)) }
            let value=text(item,kAXValueAttribute)
            let structural=["AXGroup","AXSplitGroup","AXRow","AXCell","AXToolbar","AXUnknown"].contains(role)
            if structural && label.isEmpty && value.isEmpty && actions.isEmpty { continue }
            let key=String(output.count)
            nodes[key]=item
            output.append(.object(["element_id":.string(key),"role":.string(role.isEmpty ? "AXUnknown":role),"label":.string(String(label.prefix(160))),"value":.string(String(text(item,kAXValueAttribute).prefix(160))),"actions":.array(actions.map{.string(String($0.prefix(80)))})]))
        }
        let sid=UUID().uuidString.lowercased();snapshotID=sid;snapshotAt=Date()
        var result:[String:JSON]=["snapshot_id":.string(sid),"bundle_id":.string(observedBundle),"expires_at":.string(WireTime.text(snapshotAt.addingTimeInterval(30))),"elements":.array(output),"truncated":.bool(!queue.isEmpty)]
        if params["include_image"] == .bool(true) {
            guard let bounds=rect(w) else { throw ContractError(code:"desktop_window_unavailable") }
            // ScreenCaptureKit is the authority for its own permission. The legacy
            // CoreGraphics preflight can disagree with the grant shown by macOS.
            let content: SCShareableContent
            do { content=try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true) }
            catch {
                invalidate()
                if (error as NSError).code == -3801 { throw ContractError(code:"screen_recording_permission_required") }
                throw ContractError(code:"desktop_capture_failed")
            }
            let candidates=content.windows.filter{$0.owningApplication?.processID==app.processIdentifier && abs($0.frame.width-bounds.width)<3 && abs($0.frame.height-bounds.height)<3}
            let exact=candidates.filter{abs($0.frame.minX-bounds.minX)<3 && abs($0.frame.minY-bounds.minY)<3}
            // Full-screen Chrome can expose different AX and capture origins.
            // Only fall back when there is one same-app, same-size candidate.
            // Window titles may be absent; ambiguous matches are rejected.
            guard let target = exact.count == 1 ? exact.first : (candidates.count == 1 ? candidates.first : nil) else { throw ContractError(code:"desktop_capture_window_mismatch") }
            let config=SCStreamConfiguration();let scale=min(1,640/max(bounds.width,bounds.height));config.width=max(1,Int(bounds.width*scale));config.height=max(1,Int(bounds.height*scale));config.showsCursor=false;config.ignoreShadowsSingleWindow=true
            let image=try await SCScreenshotManager.captureImage(contentFilter:SCContentFilter(desktopIndependentWindow:target),configuration:config)
            let rep=NSBitmapImageRep(cgImage:image)
            var encoded:Data?
            for quality in [0.5,0.3,0.15,0.05] { if let d=rep.representation(using:.jpeg,properties:[.compressionFactor:quality]),d.count<=24000 { encoded=d;break } }
            guard let encoded else { throw ContractError(code:"desktop_image_too_large") }
            imageSize=CGSize(width:image.width,height:image.height)
            result["image"] = .object(["mime_type":.string("image/jpeg"),"base64":.string(encoded.base64EncodedString()),"width":.number(Double(image.width)),"height":.number(Double(image.height))])
        }
        guard epoch == capturedEpoch else { invalidate(); throw ContractError(code:"desktop_permission_required") }
        _ = try check();guard NSWorkspace.shared.frontmostApplication?.processIdentifier==pid else { invalidate();throw ContractError(code:"desktop_focus_changed") }
        guard CFEqual(try safeWindow(app),w) else { invalidate();throw ContractError(code:"desktop_focus_changed") }
        let data=JSON.object(result);guard try data.data().count<58000 else { invalidate();throw ContractError(code:"desktop_observation_too_large") }
        return data
    }
    public func act(_ params: JSON) throws -> JSON {
        guard !observing else { throw ContractError(code:"desktop_busy") }
        let app=try check(bundleID)
        guard params["snapshot_id"]?.string==snapshotID,snapshotID != nil,Date().timeIntervalSince(snapshotAt)<30 else { throw ContractError(code:"desktop_snapshot_expired") }
        guard app.processIdentifier==pid,NSWorkspace.shared.frontmostApplication?.processIdentifier==pid,let w=window,CFEqual(try safeWindow(app),w) else { invalidate();throw ContractError(code:"desktop_focus_changed") }
        defer { invalidate() }
        let operation=params["operation"]?.string ?? ""
        let root=AXUIElementCreateApplication(pid)
        if let focus=attribute(root,kAXFocusedUIElementAttribute),CFGetTypeID(focus)==AXUIElementGetTypeID(),secure(focus as! AXUIElement) { throw ContractError(code:"desktop_protected_ui") }
        if operation=="type_text" {
            guard let value=params["text"]?.string,!value.isEmpty,value.count<=2000 else { throw ContractError(code:"invalid_params") }
            let characters=Array(value.utf16)
            guard let down=CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:true),let up=CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:false) else { throw ContractError(code:"desktop_action_failed") }
            characters.withUnsafeBufferPointer { buffer in
                down.keyboardSetUnicodeString(stringLength:buffer.count,unicodeString:buffer.baseAddress)
                up.keyboardSetUnicodeString(stringLength:buffer.count,unicodeString:buffer.baseAddress)
            }
            down.postToPid(pid);up.postToPid(pid)
        } else if operation=="key" {
            let codes:[String:CGKeyCode]=["return":36,"tab":48,"escape":53,"up":126,"down":125,"left":123,"right":124,"backspace":51,"space":49,"select_all":0,"home":115,"end":119,"page_up":116,"page_down":121]
            guard let key=params["key"]?.string,let code=codes[key] else { throw ContractError(code:"invalid_params") }
            guard let down=CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:true),let up=CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:false) else { throw ContractError(code:"desktop_action_failed") }
            if key=="select_all" {down.flags = .maskCommand;up.flags = .maskCommand};down.postToPid(pid);up.postToPid(pid)
        } else if operation=="click" {
            guard let imageSize,let bounds=rect(w),let x=params["x"]?.number,let y=params["y"]?.number,x>=0,y>=0,x<imageSize.width,y<imageSize.height else { throw ContractError(code:"desktop_image_required") }
            let point=CGPoint(x:bounds.minX+x/imageSize.width*bounds.width,y:bounds.minY+y/imageSize.height*bounds.height)
            var target:AXUIElement?
            guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),Float(point.x),Float(point.y),&target) == .success,let target else { throw ContractError(code:"desktop_target_unavailable") }
            var targetPID:pid_t=0;AXUIElementGetPid(target,&targetPID)
            guard targetPID==pid,!secure(target) else { throw ContractError(code:"desktop_protected_ui") }
            let right = params["button"]?.string == "right"
            let count = Int(params["click_count"]?.number ?? 1)
            for click in 1...max(1,min(2,count)) {
                guard let down=CGEvent(mouseEventSource:nil,mouseType:right ? .rightMouseDown:.leftMouseDown,mouseCursorPosition:point,mouseButton:right ? .right:.left),let up=CGEvent(mouseEventSource:nil,mouseType:right ? .rightMouseUp:.leftMouseUp,mouseCursorPosition:point,mouseButton:right ? .right:.left) else { throw ContractError(code:"desktop_action_failed") }
                down.setIntegerValueField(.mouseEventClickState,value:Int64(click));up.setIntegerValueField(.mouseEventClickState,value:Int64(click))
                // Deliver actual cursor events. PID-only events were accepted without
                // activating SwiftUI controls in the System Settings acceptance test.
                if let move=CGEvent(mouseEventSource:nil,mouseType:.mouseMoved,mouseCursorPosition:point,mouseButton:right ? .right:.left) { move.post(tap:.cghidEventTap) }
                down.post(tap:.cghidEventTap);up.post(tap:.cghidEventTap)
            }
        } else {
            guard let key=params["element_id"]?.string,let element=nodes[key],!secure(element) else { throw ContractError(code:"desktop_target_unavailable") }
            var targetPID:pid_t=0;AXUIElementGetPid(element,&targetPID);guard targetPID==pid else { throw ContractError(code:"desktop_target_unavailable") }
            let status:AXError
            switch operation {
            case "press":status=AXUIElementPerformAction(element,kAXPressAction as CFString)
            case "type":
                guard let value=params["text"]?.string,value.count<=2000,["AXTextField","AXTextArea","AXComboBox"].contains(text(element,kAXRoleAttribute)) else { throw ContractError(code:"desktop_target_not_editable") }
                var settable=DarwinBoolean(false);guard AXUIElementIsAttributeSettable(element,kAXValueAttribute as CFString,&settable) == .success,settable.boolValue else { throw ContractError(code:"desktop_target_not_editable") }
                status=AXUIElementSetAttributeValue(element,kAXValueAttribute as CFString,value as CFString)
            case "scroll":
                let up=params["direction"]?.string=="up"
                // Chromium can acknowledge AX page scrolling without moving its web viewport.
                let native:AXError = text(element,kAXRoleAttribute)=="AXWebArea" ? .actionUnsupported : AXUIElementPerformAction(element,(up ? "AXScrollUpByPage":"AXScrollDownByPage") as CFString)
                if native == .success { status=native }
                else {
                    guard ["AXScrollArea","AXWebArea"].contains(text(element,kAXRoleAttribute)),let bounds=rect(element),let windowBounds=rect(w) else { throw ContractError(code:"desktop_action_failed") }
                    let visible=bounds.intersection(windowBounds)
                    guard !visible.isNull,visible.width>0,visible.height>0 else { throw ContractError(code:"desktop_target_unavailable") }
                    let point=CGPoint(x:visible.midX,y:visible.midY)
                    var hit:AXUIElement?
                    guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),Float(point.x),Float(point.y),&hit) == .success,let hit,!secure(hit) else { throw ContractError(code:"desktop_protected_ui") }
                    var hitPID:pid_t=0;AXUIElementGetPid(hit,&hitPID)
                    guard hitPID==pid else { throw ContractError(code:"desktop_focus_changed") }
                    let pixels=Int32(min(600,max(100,visible.height*0.75)))
                    guard let event=CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:1,wheel1:up ? pixels : -pixels,wheel2:0,wheel3:0) else { throw ContractError(code:"desktop_action_failed") }
                    if let move=CGEvent(mouseEventSource:nil,mouseType:.mouseMoved,mouseCursorPosition:point,mouseButton:.left) { move.post(tap:.cghidEventTap) }
                    event.location=point;event.post(tap:.cghidEventTap);status = .success
                }
            default:throw ContractError(code:"invalid_params")
            }
            guard status == .success else { throw ContractError(code:"desktop_action_failed") }
        }
        // Success means input delivered, not task complete. Muse must observe the outcome.
        return .object([:])
    }
}
