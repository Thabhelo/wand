import AppKit
@preconcurrency import ApplicationServices
import ScreenCaptureKit
import MacBridgeCore

/// Muse owns planning. This executor only observes or performs one locally authorized step.
/// Grants and AX references are memory-only and disappear on stop, lock, sleep or restart.
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
    public init() {}
    public var active: Bool { bundleID != nil && deadline > Date() }
    public func stop() { epoch &+= 1; bundleID = nil; approvedApps = []; deadline = .distantPast; invalidate() }
    private func invalidate() { snapshotID = nil; nodes.removeAll(); window = nil; imageSize = nil }
    public static func allowedBundle(_ id: String) -> Bool {
        // These are explicit exclusions, not a claim that GUI access cannot execute code.
        !["com.apple.SecurityAgent", "com.apple.loginwindow", "com.apple.systempreferences", "com.apple.keychainaccess", "com.apple.Passwords", "com.apple.Terminal", "com.googlecode.iterm2", "local.macbridge.agent"].contains(id)
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
        guard active, let bundleID else { stop(); throw ContractError(code: "desktop_permission_required") }
        let requested = expected ?? bundleID
        guard approvedApps.contains(requested) else { throw ContractError(code: "desktop_app_not_allowed") }
        self.bundleID = requested
        guard LockStateReader.read() == .unlocked else { stop(); throw ContractError(code: "device_locked") }
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
        var output:[JSON]=[];var queue=[w];var visited=Set<CFHashCode>();var count=0
        let end=Date().addingTimeInterval(3)
        while !queue.isEmpty && output.count<60 && count<160 && Date()<end {
            let item=queue.removeFirst();count+=1
            guard visited.insert(CFHash(item)).inserted else { continue }
            AXUIElementSetMessagingTimeout(item,0.15)
            if secure(item) { continue }
            let role=text(item,kAXRoleAttribute)
            var names:CFArray?;_ = AXUIElementCopyActionNames(item,&names)
            let actions=(names as? [String] ?? []).prefix(12)
            let title=text(item,kAXTitleAttribute);let label=title.isEmpty ? text(item,kAXDescriptionAttribute) : title
            let key=String(output.count)
            nodes[key]=item
            output.append(.object(["element_id":.string(key),"role":.string(role.isEmpty ? "AXUnknown":role),"label":.string(String(label.prefix(160))),"value":.string(String(text(item,kAXValueAttribute).prefix(160))),"actions":.array(actions.map{.string(String($0.prefix(80)))})]))
            if let children=attribute(item,kAXChildrenAttribute) as? [AXUIElement] { queue.append(contentsOf:children.prefix(160)) }
        }
        let sid=UUID().uuidString.lowercased();snapshotID=sid;snapshotAt=Date()
        var result:[String:JSON]=["snapshot_id":.string(sid),"bundle_id":.string(observedBundle),"expires_at":.string(WireTime.text(snapshotAt.addingTimeInterval(30))),"elements":.array(output),"truncated":.bool(!queue.isEmpty)]
        if params["include_image"] == .bool(true) {
            guard CGPreflightScreenCaptureAccess() else { invalidate();throw ContractError(code:"screen_recording_permission_required") }
            guard let bounds=rect(w) else { throw ContractError(code:"desktop_window_unavailable") }
            let content=try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true)
            guard let target=content.windows.first(where:{$0.owningApplication?.processID==app.processIdentifier && abs($0.frame.minX-bounds.minX)<3 && abs($0.frame.minY-bounds.minY)<3 && abs($0.frame.width-bounds.width)<3 && abs($0.frame.height-bounds.height)<3}) else { throw ContractError(code:"desktop_window_unavailable") }
            let config=SCStreamConfiguration();let scale=min(1,640/max(bounds.width,bounds.height));config.width=max(1,Int(bounds.width*scale));config.height=max(1,Int(bounds.height*scale));config.showsCursor=false
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
        let data=JSON.object(result);guard try data.data().count<58000 else { invalidate();throw ContractError(code:"desktop_observation_too_large") }
        return data
    }
    public func act(_ params: JSON) throws -> JSON {
        guard !observing else { throw ContractError(code:"desktop_busy") }
        let app=try check()
        guard params["snapshot_id"]?.string==snapshotID,snapshotID != nil,Date().timeIntervalSince(snapshotAt)<30 else { throw ContractError(code:"desktop_snapshot_expired") }
        guard app.processIdentifier==pid,NSWorkspace.shared.frontmostApplication?.processIdentifier==pid,let w=window,CFEqual(try safeWindow(app),w) else { invalidate();throw ContractError(code:"desktop_focus_changed") }
        defer { invalidate() }
        let operation=params["operation"]?.string ?? ""
        let root=AXUIElementCreateApplication(pid)
        if let focus=attribute(root,kAXFocusedUIElementAttribute),CFGetTypeID(focus)==AXUIElementGetTypeID(),secure(focus as! AXUIElement) { throw ContractError(code:"desktop_protected_ui") }
        if operation=="key" {
            let codes:[String:CGKeyCode]=["return":36,"tab":48,"escape":53,"up":126,"down":125,"left":123,"right":124,"backspace":51,"space":49,"select_all":0]
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
            guard let down=CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:point,mouseButton:.left),let up=CGEvent(mouseEventSource:nil,mouseType:.leftMouseUp,mouseCursorPosition:point,mouseButton:.left) else { throw ContractError(code:"desktop_action_failed") };down.postToPid(pid);up.postToPid(pid)
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
            case "scroll":status=AXUIElementPerformAction(element,(params["direction"]?.string=="up" ? "AXScrollUpByPage":"AXScrollDownByPage") as CFString)
            default:throw ContractError(code:"invalid_params")
            }
            guard status == .success else { throw ContractError(code:"desktop_action_failed") }
        }
        // Success means input delivered, not task complete. Muse must observe the outcome.
        return .object([:])
    }
}
