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
    private var imageBounds: CGRect?
    private var observedTitle: String?
    private let defaults: UserDefaults?
    public var desktopWide: Bool { defaults?.bool(forKey: "desktop-control-consent-v1") == true }
    public init(defaults: UserDefaults? = nil) { self.defaults = defaults }
    public func enableDesktop() { suspend(); defaults?.set(true, forKey: "desktop-control-consent-v1") }
    public func suspend() { epoch &+= 1; invalidate() }
    public var active: Bool { desktopWide || (bundleID != nil && deadline > Date()) }
    public func stop() { defaults?.set(false, forKey: "desktop-control-consent-v1"); epoch &+= 1; bundleID = nil; approvedApps = []; deadline = .distantPast; invalidate() }
    private func invalidate() { snapshotID = nil; nodes.removeAll(); window = nil; imageSize = nil; imageBounds = nil; observedTitle = nil }
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
    struct ObservationWindow {
        let processID: pid_t
        let role: String
        let subrole: String
        let minimized: Bool?
        let bounds: CGRect?
        var usable: Bool {
            guard role=="AXWindow", minimized==false, let bounds else { return false }
            return bounds.minX.isFinite && bounds.minY.isFinite && bounds.width.isFinite && bounds.height.isFinite && bounds.width>0 && bounds.height>0
        }
    }
    static func observationWindowIndex(_ windows: [ObservationWindow], processID: pid_t, focused: Int?, main: Int?) throws -> Int {
        if let focused, windows.indices.contains(focused) {
            let window=windows[focused]
            guard window.processID==processID, window.subrole != "AXSystemDialog" else { throw ContractError(code:"desktop_protected_ui") }
            guard window.usable else { throw ContractError(code:"desktop_window_unavailable") }
            return focused
        }
        // With no focused window, never select a normal window behind protected UI.
        guard !windows.contains(where:{$0.subrole=="AXSystemDialog"}) else { throw ContractError(code:"desktop_protected_ui") }
        let eligible=windows.indices.filter { windows[$0].processID==processID && windows[$0].subrole=="AXStandardWindow" && windows[$0].usable }
        if let main, eligible.contains(main) { return main }
        guard eligible.count==1, let selected=eligible.first else { throw ContractError(code:"desktop_window_unavailable") }
        return selected
    }
    private enum ObservationPreparationError: Error { case timeout }
    private func observationWindow(_ app: NSRunningApplication, deadline: Date) throws -> AXUIElement {
        let root=AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root,0.2)
        func checkBudget() throws {
            guard Date()<deadline else { throw ObservationPreparationError.timeout }
        }
        func read(_ element: AXUIElement, _ name: String) throws -> CFTypeRef? {
            try checkBudget()
            let value=attribute(element,name)
            try checkBudget()
            return value
        }
        func candidate(_ window: AXUIElement) throws -> ObservationWindow {
            AXUIElementSetMessagingTimeout(window,0.2)
            var processID:pid_t=0
            try checkBudget()
            _ = AXUIElementGetPid(window,&processID)
            let role=try read(window,kAXRoleAttribute) as? String ?? ""
            let subrole=try read(window,kAXSubroleAttribute) as? String ?? ""
            let minimized=(try read(window,kAXMinimizedAttribute) as? NSNumber)?.boolValue
            try checkBudget()
            let bounds=rect(window)
            try checkBudget()
            return ObservationWindow(processID:processID,role:role,subrole:subrole,minimized:minimized,bounds:bounds)
        }
        if let focused=try read(root,kAXFocusedWindowAttribute), CFGetTypeID(focused)==AXUIElementGetTypeID() {
            let window=focused as! AXUIElement
            _ = try Self.observationWindowIndex([try candidate(window)],processID:app.processIdentifier,focused:0,main:nil)
            return window
        }
        var windows=try read(root,kAXWindowsAttribute) as? [AXUIElement] ?? []
        guard windows.count<=30 else { throw ContractError(code:"desktop_window_unavailable") }
        var main:Int?
        if let value=try read(root,kAXMainWindowAttribute), CFGetTypeID(value)==AXUIElementGetTypeID() {
            let window=value as! AXUIElement
            if let existing=windows.firstIndex(where:{CFEqual($0,window)}) { main=existing }
            else { main=windows.count; windows.append(window) }
        }
        return windows[try Self.observationWindowIndex(windows.map(candidate),processID:app.processIdentifier,focused:nil,main:main)]
    }
    static func confirmObservationFocus(matches: () throws -> Bool,
                                        pause: () async throws -> Void = { try await Task.sleep(for:.milliseconds(100)) }) async throws {
        for attempt in 0..<12 {
            if try matches() { return }
            if attempt<11 { try await pause() }
        }
        throw ContractError(code:"desktop_focus_changed")
    }
    private func prepareObservationWindow(_ app: NSRunningApplication, capturedEpoch: UInt64) async throws -> AXUIElement {
        var selected:AXUIElement?
        let deadline=Date().addingTimeInterval(2)
        for _ in 0..<12 {
            try await Task.sleep(for:.milliseconds(100))
            guard epoch==capturedEpoch else { throw ContractError(code:"desktop_permission_required") }
            _ = try check(app.bundleIdentifier)
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier==app.processIdentifier else { continue }
            do { selected=try observationWindow(app,deadline:deadline); break }
            catch ObservationPreparationError.timeout { throw ContractError(code:"desktop_window_unavailable") }
            catch let error as ContractError where error.code=="desktop_window_unavailable" { continue }
        }
        guard epoch==capturedEpoch else { throw ContractError(code:"desktop_permission_required") }
        _ = try check(app.bundleIdentifier)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier==app.processIdentifier else { throw ContractError(code:"desktop_focus_changed") }
        guard let selected else { throw ContractError(code:"desktop_window_unavailable") }
        // Activation alone can leave a visible window unfocused or on another Space.
        // An AX acknowledgement is not proof: require this exact window to become focused.
        _ = AXUIElementPerformAction(selected,kAXRaiseAction as CFString)
        try await Self.confirmObservationFocus(matches:{
            guard self.epoch==capturedEpoch else { throw ContractError(code:"desktop_permission_required") }
            _ = try self.check(app.bundleIdentifier)
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier==app.processIdentifier else { return false }
            do { return CFEqual(try self.safeWindow(app),selected) }
            catch let error as ContractError where error.code=="desktop_window_unavailable" { return false }
        })
        return selected
    }
    public func observe(_ params: JSON) async throws -> JSON {
        guard !observing else { throw ContractError(code:"desktop_busy") }
        observing = true; defer { observing = false }
        let app=try check(params["bundle_id"]?.string)
        let capturedEpoch = epoch
        let observedBundle = app.bundleIdentifier ?? ""
        app.activate()
        let w=try await prepareObservationWindow(app,capturedEpoch:capturedEpoch)
        guard epoch == capturedEpoch else { throw ContractError(code:"desktop_permission_required") }
        _ = try check(observedBundle)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { throw ContractError(code:"desktop_focus_changed") }
        invalidate();window=w;pid=app.processIdentifier;observedTitle=text(w,kAXTitleAttribute)
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
            guard let currentBounds=rect(w) else { throw ContractError(code:"desktop_capture_window_mismatch") }
            func validateCapture() throws {
                guard epoch==capturedEpoch else { throw ContractError(code:"desktop_permission_required") }
                _ = try check(observedBundle)
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier==app.processIdentifier,
                      CFEqual(try safeWindow(app),w),text(w,kAXTitleAttribute)==observedTitle,
                      let bounds=rect(w),Self.sameBounds(bounds,currentBounds) else { throw ContractError(code:"desktop_focus_changed") }
            }
            // ScreenCaptureKit is the authority for its own permission. The legacy
            // CoreGraphics preflight can disagree with the grant shown by macOS.
            var unavailableCode="desktop_capture_failed"
            let target:SCWindow? = try await Self.awaitCaptureTarget(lookup:{
                let content:SCShareableContent
                do { content=try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true) }
                catch {
                    self.invalidate()
                    if (error as NSError).code == -3801 { throw ContractError(code:"screen_recording_permission_required") }
                    throw ContractError(code:"desktop_capture_failed")
                }
                try validateCapture()
                // A newly raised window can be absent from SCK's first enumeration.
                // Retry only the same app/window; never broaden capture to another layer.
                let windows=content.windows.filter{$0.owningApplication?.processID==app.processIdentifier}
                guard windows.contains(where:{$0.windowLayer==0}) else { unavailableCode="desktop_capture_failed"; return nil }
                let candidates=windows.map{CaptureWindow(id:$0.windowID,bounds:$0.frame,layer:$0.windowLayer,title:$0.title ?? "")}
                guard let targetID=Self.captureWindow(candidates,bounds:currentBounds,title:self.text(w,kAXTitleAttribute)),
                      let target=windows.first(where:{$0.windowID==targetID}) else {
                    unavailableCode="desktop_capture_window_mismatch"
                    return nil
                }
                return target
            },validate:validateCapture)
            guard let target else {
                invalidate()
                throw ContractError(code:unavailableCode)
            }
            try validateCapture()
            let config=SCStreamConfiguration();let scale=min(1,640/max(currentBounds.width,currentBounds.height));config.width=max(1,Int(currentBounds.width*scale));config.height=max(1,Int(currentBounds.height*scale));config.showsCursor=false;config.ignoreShadowsSingleWindow=true
            let image=try await SCScreenshotManager.captureImage(contentFilter:SCContentFilter(desktopIndependentWindow:target),configuration:config)
            try validateCapture()
            let encoded=try Self.encodeScreenshot(image)
            imageSize=encoded.size;imageBounds=currentBounds
            result["image"] = .object(["mime_type":.string("image/jpeg"),"base64":.string(encoded.data.base64EncodedString()),"width":.number(Double(encoded.size.width)),"height":.number(Double(encoded.size.height))])
        }
        guard epoch == capturedEpoch else { invalidate(); throw ContractError(code:"desktop_permission_required") }
        _ = try check();guard NSWorkspace.shared.frontmostApplication?.processIdentifier==pid else { invalidate();throw ContractError(code:"desktop_focus_changed") }
        guard CFEqual(try safeWindow(app),w),text(w,kAXTitleAttribute)==observedTitle else { invalidate();throw ContractError(code:"desktop_focus_changed") }
        let data=JSON.object(result);guard try data.data().count<58000 else { invalidate();throw ContractError(code:"desktop_observation_too_large") }
        return data
    }
    static func awaitCaptureTarget<T>(lookup: () async throws -> T?, validate: () throws -> Void,
                                      pause: () async throws -> Void = { try await Task.sleep(for:.milliseconds(200)) },
                                      now: () -> Date = Date.init) async throws -> T? {
        let deadline=now().addingTimeInterval(2)
        for attempt in 0..<3 {
            try validate()
            guard now()<deadline else { return nil }
            let target=try await lookup()
            try validate()
            guard now()<deadline else { return nil }
            if let target { return target }
            if attempt<2 { try await pause() }
        }
        return nil
    }
    struct CaptureWindow {
        let id:CGWindowID
        let bounds:CGRect
        let layer:Int
        let title:String
    }
    static func sameBounds(_ a:CGRect,_ b:CGRect)->Bool {
        abs(a.minX-b.minX)<3 && abs(a.minY-b.minY)<3 && abs(a.width-b.width)<3 && abs(a.height-b.height)<3
    }
    static func captureWindow(_ windows:[CaptureWindow],bounds:CGRect,title:String)->CGWindowID? {
        let candidates=windows.filter{$0.layer==0 && abs($0.bounds.width-bounds.width)<3 && abs($0.bounds.height-bounds.height)<3}
        let exact=candidates.filter{sameBounds($0.bounds,bounds)}
        if exact.count==1 { return exact[0].id }
        // A title can disambiguate same-geometry windows, but never override geometry.
        let named=exact.filter{!title.isEmpty && $0.title==title}
        if named.count==1 { return named[0].id }
        return nil
    }
    static func encodeScreenshot(_ image:CGImage,byteLimit:Int=24000) throws -> (data:Data,size:CGSize) {
        // Explicitly resize: display scale can make SCK return more pixels than requested.
        // Reduce resolution as well as quality so text-rich/noisy windows stay within the wire limit.
        for edge in [640,512,384,256,192,128] {
            let scale=min(1,Double(edge)/Double(max(image.width,image.height)))
            let width=max(1,Int(Double(image.width)*scale)),height=max(1,Int(Double(image.height)*scale))
            guard let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else { continue }
            context.setFillColor(NSColor.white.cgColor);context.fill(CGRect(x:0,y:0,width:width,height:height))
            context.interpolationQuality = .high
            context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
            guard let resized=context.makeImage() else { continue }
            let rep=NSBitmapImageRep(cgImage:resized)
            for quality in [0.65,0.45,0.25] {
                if let data=rep.representation(using:.jpeg,properties:[.compressionFactor:quality]),data.count<=byteLimit {
                    return (data,CGSize(width:width,height:height))
                }
            }
        }
        throw ContractError(code:"desktop_image_too_large")
    }
    private static func postKey(_ key:CGKeyCode,pid:pid_t,flags:CGEventFlags=[]) throws {
        guard let down=CGEvent(keyboardEventSource:nil,virtualKey:key,keyDown:true),let up=CGEvent(keyboardEventSource:nil,virtualKey:key,keyDown:false) else { throw ContractError(code:"desktop_action_failed") }
        down.flags=flags;up.flags=flags;down.postToPid(pid);up.postToPid(pid)
    }
    public func act(_ params: JSON) throws -> JSON {
        guard !observing else { throw ContractError(code:"desktop_busy") }
        let app=try check(bundleID)
        guard params["snapshot_id"]?.string==snapshotID,snapshotID != nil,Date().timeIntervalSince(snapshotAt)<30 else { throw ContractError(code:"desktop_snapshot_expired") }
        guard app.processIdentifier==pid,NSWorkspace.shared.frontmostApplication?.processIdentifier==pid,let w=window,CFEqual(try safeWindow(app),w),text(w,kAXTitleAttribute)==observedTitle else { invalidate();throw ContractError(code:"desktop_focus_changed") }
        defer { invalidate() }
        let operation=params["operation"]?.string ?? ""
        let root=AXUIElementCreateApplication(pid)
        if let focus=attribute(root,kAXFocusedUIElementAttribute),CFGetTypeID(focus)==AXUIElementGetTypeID(),secure(focus as! AXUIElement) { throw ContractError(code:"desktop_protected_ui") }
        if operation=="type_text" {
            guard let value=params["text"]?.string,!value.isEmpty,value.count<=2000 else { throw ContractError(code:"invalid_params") }
            let characters=Array(value.utf16)
            guard let down=CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:true),let up=CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:false) else { throw ContractError(code:"desktop_action_failed") }
            down.flags=[];up.flags=[]
            characters.withUnsafeBufferPointer { buffer in
                down.keyboardSetUnicodeString(stringLength:buffer.count,unicodeString:buffer.baseAddress)
                up.keyboardSetUnicodeString(stringLength:buffer.count,unicodeString:buffer.baseAddress)
            }
            down.postToPid(pid);up.postToPid(pid)
        } else if operation=="key" {
            let codes:[String:CGKeyCode]=["return":36,"tab":48,"escape":53,"up":126,"down":125,"left":123,"right":124,"backspace":51,"space":49,"select_all":0,"home":115,"end":119,"page_up":116,"page_down":121]
            guard let key=params["key"]?.string,let code=codes[key] else { throw ContractError(code:"invalid_params") }
            guard let down=CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:true),let up=CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:false) else { throw ContractError(code:"desktop_action_failed") }
            down.flags=[];up.flags=[]
            if key=="select_all" {down.flags = .maskCommand;up.flags = .maskCommand};down.postToPid(pid);up.postToPid(pid)
        } else if operation=="click" {
            guard let imageSize,let bounds=rect(w),let x=params["x"]?.number,let y=params["y"]?.number,x>=0,y>=0,x<imageSize.width,y<imageSize.height else { throw ContractError(code:"desktop_image_required") }
            guard let imageBounds,Self.sameBounds(bounds,imageBounds) else { throw ContractError(code:"desktop_focus_changed") }
            let point=CGPoint(x:bounds.minX+x/imageSize.width*bounds.width,y:bounds.minY+y/imageSize.height*bounds.height)
            var target:AXUIElement?
            guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),Float(point.x),Float(point.y),&target) == .success,let target else { throw ContractError(code:"desktop_target_unavailable") }
            var targetPID:pid_t=0;AXUIElementGetPid(target,&targetPID)
            guard targetPID==pid,!secure(target) else { throw ContractError(code:"desktop_protected_ui") }
            let right = params["button"]?.string == "right"
            let count = Int(params["click_count"]?.number ?? 1)
            for click in 1...max(1,min(2,count)) {
                guard let down=CGEvent(mouseEventSource:nil,mouseType:right ? .rightMouseDown:.leftMouseDown,mouseCursorPosition:point,mouseButton:right ? .right:.left),let up=CGEvent(mouseEventSource:nil,mouseType:right ? .rightMouseUp:.leftMouseUp,mouseCursorPosition:point,mouseButton:right ? .right:.left) else { throw ContractError(code:"desktop_action_failed") }
                down.flags=[];up.flags=[]
                down.setIntegerValueField(.mouseEventClickState,value:Int64(click));up.setIntegerValueField(.mouseEventClickState,value:Int64(click))
                // Deliver actual cursor events. PID-only events were accepted without
                // activating SwiftUI controls in the System Settings acceptance test.
                if let move=CGEvent(mouseEventSource:nil,mouseType:.mouseMoved,mouseCursorPosition:point,mouseButton:right ? .right:.left) { move.flags=[];move.post(tap:.cghidEventTap) }
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
                // Native keyboard entry does not require AXValue to be writable (Chromium).
                // AXValue alone does not emit editing events in apps such as Font Book.
                // Focus exactly the observed editable field, then replace via normal input.
                func isFocused() -> Bool {
                    guard let focused=attribute(root,kAXFocusedUIElementAttribute),CFGetTypeID(focused)==AXUIElementGetTypeID() else { return false }
                    return CFEqual(focused,element)
                }
                _ = AXUIElementSetAttributeValue(element,kAXFocusedAttribute as CFString,kCFBooleanTrue)
                // Chromium applies focus asynchronously and may acknowledge AXFocused
                // without moving web focus. AXPress supplies its native focus action.
                if !isFocused() { _ = AXUIElementPerformAction(element,kAXPressAction as CFString) }
                for _ in 0..<10 {
                    if isFocused() { break }
                    Thread.sleep(forTimeInterval:0.02)
                }
                guard isFocused() else { throw ContractError(code:"desktop_target_not_editable") }
                _ = try check(bundleID)
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier==pid,
                      CFEqual(try safeWindow(app),w),text(w,kAXTitleAttribute)==observedTitle else { throw ContractError(code:"desktop_focus_changed") }
                try Self.postKey(0,pid:pid,flags:.maskCommand)
                if value.isEmpty { try Self.postKey(51,pid:pid) }
                else {
                    let characters=Array(value.utf16)
                    guard let down=CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:true),let up=CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:false) else { throw ContractError(code:"desktop_action_failed") }
                    down.flags=[];up.flags=[]
                    characters.withUnsafeBufferPointer { buffer in
                        down.keyboardSetUnicodeString(stringLength:buffer.count,unicodeString:buffer.baseAddress)
                        up.keyboardSetUnicodeString(stringLength:buffer.count,unicodeString:buffer.baseAddress)
                    }
                    down.postToPid(pid);up.postToPid(pid)
                }
                status = .success
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
                    if let move=CGEvent(mouseEventSource:nil,mouseType:.mouseMoved,mouseCursorPosition:point,mouseButton:.left) { move.flags=[];move.post(tap:.cghidEventTap) }
                    event.flags=[];event.location=point;event.post(tap:.cghidEventTap);status = .success
                }
            default:throw ContractError(code:"invalid_params")
            }
            guard status == .success else { throw ContractError(code:"desktop_action_failed") }
        }
        // Success means input delivered, not task complete. Muse must observe the outcome.
        return .object([:])
    }
}
