import AppKit
import Combine
import CoreImage.CIFilterBuiltins
import MacBridgeCore
import MacBridgeNative

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var agent: Agent?
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var observation: AnyCancellable?
    private var selected = 0
    private var compact = false
    private var responsiveRows: [NSStackView] = []
    private var sidebarView: NSView?
    private var sidebarWidth: NSLayoutConstraint?
    private var contentTop: NSLayoutConstraint?
    private var contentInsets: [NSLayoutConstraint] = []
    private let pagePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let body = NSStackView()
    private let result = NSTextField(wrappingLabelWithString: "")
    private var feedbackTask: Task<Void, Never>?
    private var displayedCommand = ""
    private let state = NSTextField(wrappingLabelWithString: "Checking this Mac…")
    private let details = NSTextField(wrappingLabelWithString: "")
    private let statusRows = NSStackView()
    private var statusSignature = ""
    private let desktopStatus = NSTextField(wrappingLabelWithString: "Desktop control is off")
    private let connection = NSTextField(wrappingLabelWithString: "")
    private var connectButton: NSButton?
    private var pairingActions: NSStackView?
    private var pairingFallback: NSStackView?
    private var pairingHelpButton: NSButton?
    private var copyPairingButton: NSButton?
    private var advancedView: NSView?
    private let pairingQR = NSImageView()
    private let phoneQR = NSImageView()
    private let loginToggle = NSButton(checkboxWithTitle: "Start Wand when I log in", target: nil, action: nil)
    private let loginStatus = NSTextField(wrappingLabelWithString: "")
    private var phoneSharePicker: NSSharingServicePicker?
    private var phoneHandoff: NSView?
    private var phoneURL = ""
    private var qrCode = ""
    private let codeLabel = NSTextField(labelWithString: "")
    private let website = NSTextField(string: "")
    private let relay = NSTextField(string: "")
    private let shortcut = NSTextField(string: "")
    private let appName = NSTextField(string: "")
    private let appPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private var installedApps: [AppInventory.Entry] = []
    private let cleanupBrowser = NSPopUpButton(frame: .zero, pullsDown: false)
    private let shortcutsList = NSStackView()
    private let activityList = NSStackView()
    private let volume = NSSlider(value: 30, minValue: 0, maxValue: 100, target: nil, action: nil)
    private var navigation: [NSButton] = []
    private var controls: [NSButton] = []
    private var readButton: NSButton?
    private var shortcutSnapshot: [String] = []
    private var activitySnapshot = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow(); buildMenu()
        // First launch shows setup; later launches run quietly. The menu icon and
        // reopening the app always provide an explicit way to show the window.
        if !UserDefaults.standard.bool(forKey: "wand-has-launched") { showWindow() }
        UserDefaults.standard.set(true, forKey: "wand-has-launched")
        StartupSettings.enableOnceIfInstalled()
        add(label("Opening Wand…", size: 28, weight: .semibold))
        add(label("If macOS asks, allow Wand to access its connection keys in Keychain.", secondary: true))
        Task { @MainActor [self] in
            do {
                agent = try Agent()
                buildPage()
                observation = agent?.objectWillChange.sink { [weak self] _ in
                    Task { @MainActor in self?.render() }
                }
                render(); agent?.refreshDeviceState()
                Task { @MainActor in await agent?.startConnections() }
            } catch {
                body.arrangedSubviews.forEach { body.removeArrangedSubview($0); $0.removeFromSuperview() }
                add(label("Wand couldn’t open its connection keys.", size: 22, weight: .semibold))
                add(label("Reopen Wand and approve its Keychain access when macOS asks. Your existing keys have not been deleted.", secondary: true))
            }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    @objc func showWindow() { window?.makeKeyAndOrderFront(nil); NSApplication.shared.activate(ignoringOtherApps: true) }
    private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let view = NSTextField(wrappingLabelWithString: text)
        view.font = .systemFont(ofSize: size, weight: weight)
        view.textColor = secondary ? .secondaryLabelColor : .labelColor
        return view
    }
    private func button(_ title: String, _ action: Selector, symbol: String? = nil, primary: Bool = false) -> NSButton {
        let view = NSButton(title: title, target: self, action: action)
        view.bezelStyle = .rounded; view.controlSize = .large
        view.font = .systemFont(ofSize: 13, weight: .medium)
        if let symbol { view.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil); view.imagePosition = .imageLeading }
        if primary { view.bezelColor = .systemIndigo; view.contentTintColor = .white }
        view.setAccessibilityLabel(title)
        return view
    }
    private func actionButton(_ title: String, _ action: Selector, symbol: String? = nil) -> NSButton {
        let view = button(title, action, symbol: symbol); controls.append(view); return view
    }
    private func row(_ views: NSView...) -> NSStackView {
        let stack = NSStackView(views: views); stack.orientation = compact ? .vertical : .horizontal; stack.spacing = 10; stack.alignment = compact ? .leading : .centerY
        responsiveRows.append(stack)
        return stack
    }
    private func column(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
        let stack = NSStackView(views: views); stack.orientation = .vertical; stack.spacing = spacing; stack.alignment = .leading
        return stack
    }
    private func field(_ view: NSTextField, placeholder: String) -> NSTextField {
        view.placeholderString = placeholder; view.controlSize = .large; view.font = .systemFont(ofSize: 14)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        view.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
        view.setAccessibilityLabel(placeholder)
        return view
    }
    private func card(_ title: String, subtitle: String? = nil, accessory: NSView? = nil, views: [NSView]) -> NSView {
        let heading = label(title, size: 16, weight: .semibold)
        var items: [NSView] = [accessory.map { row(heading, $0) } ?? heading]
        if let subtitle { items.append(label(subtitle, secondary: true)) }
        items.append(contentsOf: views)
        let stack = column(items)
        for item in items where item is NSStackView {
            item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        let card = CardView(); stack.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20), stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 19), stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -19)])
        return card
    }
    private func add(_ view: NSView) {
        body.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
    }
    private func buildWindow() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "Wand"; w.titleVisibility = .hidden; w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false; w.delegate = self; w.minSize = NSSize(width: 1, height: 1); w.contentMinSize = .zero
        w.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(calibratedWhite: 0.10, alpha: 1) : NSColor(red: 0.96, green: 0.955, blue: 0.975, alpha: 1)
        }
        let root = NSView(); w.contentView = root
        let sidebar = NSVisualEffectView(); sidebar.material = .sidebar; sidebar.blendingMode = .behindWindow; sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(sidebar); sidebarView = sidebar
        pagePicker.addItems(withTitles: ["This Mac", "Shortcuts", "Activity", "Connection"])
        pagePicker.target = self; pagePicker.action = #selector(pickPage)
        pagePicker.setAccessibilityLabel("Page")
        pagePicker.translatesAutoresizingMaskIntoConstraints = false; pagePicker.isHidden = true; root.addSubview(pagePicker)
        let brand = label("Wand", size: 23, weight: .semibold)
        let nav = column([brand], spacing: 12)
        nav.addArrangedSubview(NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 20)))
        for (index, item) in [("This Mac", "desktopcomputer"), ("Shortcuts", "square.stack.3d.up"), ("Activity", "clock.arrow.circlepath"), ("Connection", "link")].enumerated() {
            let itemButton = button(item.0, #selector(navigate(_:)), symbol: item.1)
            itemButton.tag = index; itemButton.bezelStyle = .recessed; itemButton.setButtonType(.pushOnPushOff); itemButton.alignment = .left
            itemButton.widthAnchor.constraint(equalToConstant: 174).isActive = true
            itemButton.heightAnchor.constraint(equalToConstant: 38).isActive = true
            nav.addArrangedSubview(itemButton); navigation.append(itemButton)
        }
        nav.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(nav)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false; scroll.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedDocumentView(); document.translatesAutoresizingMaskIntoConstraints = false
        body.orientation = .vertical; body.alignment = .leading; body.spacing = 24; body.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(body); scroll.documentView = document; root.addSubview(scroll)
        result.font = .systemFont(ofSize: 12, weight: .medium); result.textColor = .secondaryLabelColor; result.isSelectable = true
        result.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(result)
        sidebarWidth = sidebar.widthAnchor.constraint(equalToConstant: 214)
        contentTop = scroll.topAnchor.constraint(equalTo: root.topAnchor, constant: 40)
        contentInsets = [body.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 32), body.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -32)]
        let viewportWidth = document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        viewportWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            pagePicker.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12), pagePicker.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12), pagePicker.topAnchor.constraint(equalTo: root.topAnchor, constant: 34),
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor), sidebar.topAnchor.constraint(equalTo: root.topAnchor), sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor), sidebarWidth!,
            nav.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 20), nav.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 62),
            scroll.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor), contentTop!, scroll.bottomAnchor.constraint(equalTo: result.topAnchor, constant: -14),
            result.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 32), result.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32), result.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            viewportWidth, document.widthAnchor.constraint(greaterThanOrEqualToConstant: 240), contentInsets[0], contentInsets[1], body.topAnchor.constraint(equalTo: document.topAnchor, constant: 18), body.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -28)
        ])
        window = w
        if !w.setFrameUsingName("MacBridgeMainWindow") { w.center() }
        w.setFrameAutosaveName("MacBridgeMainWindow")
        updateLayout()
    }
    func windowDidResize(_ notification: Notification) { updateLayout() }
    private func updateLayout() {
        guard let window else { return }
        let next = window.frame.width < 720
        guard compact != next else { return }
        compact = next
        sidebarView?.isHidden = compact; sidebarWidth?.constant = compact ? 0 : 214
        pagePicker.isHidden = !compact; pagePicker.selectItem(at: selected)
        contentTop?.constant = compact ? 72 : 40
        contentInsets.first?.constant = compact ? 12 : 32
        contentInsets.last?.constant = compact ? -12 : -32
        for row in responsiveRows {
            row.orientation = compact ? .vertical : .horizontal
            row.alignment = compact ? .leading : .centerY
        }
    }
    @objc private func pickPage() {
        selected = pagePicker.indexOfSelectedItem; buildPage(); render()
    }
    @objc private func navigate(_ sender: NSButton) {
        guard selected != sender.tag else { sender.state = .on; return }
        selected = sender.tag; buildPage(); render()
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            body.alphaValue = 0.65
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                body.animator().alphaValue = 1
            }
        }
    }
    private func buildPage() {
        body.arrangedSubviews.forEach { body.removeArrangedSubview($0); $0.removeFromSuperview() }
        controls = []; readButton = nil; responsiveRows = []
        pagePicker.selectItem(at: selected)
        for (index, item) in navigation.enumerated() { item.state = index == selected ? .on : .off; item.contentTintColor = index == selected ? .systemIndigo : .secondaryLabelColor }
        let titles = ["This Mac", "Your Shortcuts", "Recent activity", "Stay connected"]
        add(label(titles[selected], size: 28, weight: .semibold))
        switch selected {
        case 0:
            state.font = .systemFont(ofSize: 15, weight: .medium)
            details.font = .systemFont(ofSize: 13); details.textColor = .secondaryLabelColor; details.isSelectable = true
            let refresh = button("Refresh", #selector(readState), symbol: "arrow.clockwise"); readButton = refresh
            add(card(Host.current().localizedName ?? "This Mac", accessory: refresh, views: [state, details, statusRows]))
            if volume.constraints.isEmpty {
                volume.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
                let preferred = volume.widthAnchor.constraint(equalToConstant: 220); preferred.priority = .defaultHigh; preferred.isActive = true
            }
            volume.setAccessibilityLabel("Output volume")
            volume.target = self; volume.action = #selector(setVolumeAction); volume.isContinuous = false
            volume.toolTip = "Adjust volume"
            add(card("Sound & playback", subtitle: "Playback controls use Music or Spotify when open.", views: [row(actionButton("Previous", #selector(previous), symbol: "backward.end.fill"), actionButton("Play / Pause", #selector(playPause), symbol: "playpause.fill"), actionButton("Next", #selector(next), symbol: "forward.end.fill")), row(volume, actionButton("Mute", #selector(muteSound)), actionButton("Unmute", #selector(unmuteSound)))]))
            refreshApps()
            add(card("Open something", views: [row(field(website, placeholder: "Website · https://example.com"), actionButton("Open website", #selector(openWebsite), symbol: "arrow.up.right")), row(appPicker, button("Refresh apps", #selector(refreshApps), symbol: "arrow.clockwise")), field(appName, placeholder: "Other app name or bundle ID"), row(actionButton("Open app", #selector(openApp)), actionButton("Quit app…", #selector(quitApp)))]))
            if cleanupBrowser.numberOfItems == 0 { cleanupBrowser.addItems(withTitles: ["Safari", "Chrome"]); cleanupBrowser.setAccessibilityLabel("Browser to clean up") }
            add(card("Mac controls", views: [row(actionButton("Lock…", #selector(lockMac)), actionButton("Sleep…", #selector(sleepMac))), row(actionButton("Focus on", #selector(focusOn)), actionButton("Focus off", #selector(focusOff))), row(cleanupBrowser, actionButton("Close browser tabs…", #selector(cleanSafari)))]))
        case 1:
            add(card("Add an approved Shortcut", subtitle: "Use its exact name from Apple Shortcuts. Shortcuts can run code; add only ones you trust.", views: [row(field(shortcut, placeholder: "Exact Shortcut name"), button("Add Shortcut", #selector(addShortcut), symbol: "plus", primary: true))]))
            shortcutsList.orientation = .vertical; shortcutsList.alignment = .leading; shortcutsList.spacing = 12
            add(card("Approved on this Mac", views: [shortcutsList]))
            shortcutSnapshot = []; renderShortcuts(force: true)
            add(button("Open Apple Shortcuts", #selector(openShortcuts), symbol: "arrow.up.right"))
        case 2:
            activityList.orientation = .vertical; activityList.alignment = .leading; activityList.spacing = 14
            add(card("Latest commands", subtitle: "Full parameters stay in the private log on this Mac. State responses are never recorded.", views: [activityList]))
            add(row(button("Refresh activity", #selector(refreshActivity), symbol: "arrow.clockwise"), button("Show log in Finder", #selector(showLog), symbol: "folder")))
            refreshActivity()
        default:
            connection.font = .systemFont(ofSize: 14, weight: .medium)
            codeLabel.font = .monospacedSystemFont(ofSize: 24, weight: .semibold); codeLabel.isSelectable = true
            let connect = button("Connect", #selector(pair), symbol: "link", primary: true); connectButton = connect
            pairingQR.setAccessibilityLabel("Scan to continue pairing on your phone")
            if pairingQR.constraints.isEmpty {
                pairingQR.widthAnchor.constraint(equalToConstant: 144).isActive = true
                pairingQR.heightAnchor.constraint(equalToConstant: 144).isActive = true
            }
            let copy = button("Copy code", #selector(copyPairingCode), symbol: "doc.on.doc")
            copyPairingButton = copy
            let fallback = column([
                button("Open setup page again", #selector(continuePairing), symbol: "arrow.up.right"),
                label("Or open the dashboard, choose Connect a Mac, and enter this code.", size: 12, secondary: true),
                row(codeLabel, copy),
                button("Open dashboard", #selector(dashboard), symbol: "arrow.up.right"),
                pairingQR, label("You can also scan to finish on your phone.", size: 12, secondary: true)
            ])
            fallback.isHidden = true
            pairingFallback = fallback
            let help = button("Setup page didn’t open?", #selector(togglePairingHelp), symbol: "chevron.right")
            pairingHelpButton = help
            let handoff = column([label("Sign in and approve this Mac in your browser. Wand will connect automatically.", size: 13, secondary: true), help, fallback, button("Cancel", #selector(cancelPairing))])
            pairingActions = handoff
            add(card("Connect your Mac", subtitle: "Click Connect, sign in, and approve this Mac.", views: [connect, connection, handoff]))
            add(label("Linking your Wand account prepares this Mac for remote control. Muse authorization requires the official connector; it is not included in this preview.", size: 12, secondary: true))
            phoneQR.setAccessibilityLabel("Scan to open Wand on your phone")
            if phoneQR.constraints.isEmpty {
                phoneQR.widthAnchor.constraint(equalToConstant: 160).isActive = true
                phoneQR.heightAnchor.constraint(equalToConstant: 160).isActive = true
            }
            let phoneCard = card("Use Wand on your phone", subtitle: "Scan with your phone’s camera. Sign in with the same Google account if asked.", views: [phoneQR, row(button("Send link…", #selector(sharePhoneLink), symbol: "square.and.arrow.up"), button("Copy link", #selector(copyPhoneLink))), button("Open dashboard", #selector(dashboard), symbol: "arrow.up.right")])
            phoneHandoff = phoneCard
            add(phoneCard)
            loginToggle.target = self; loginToggle.action = #selector(toggleStartAtLogin)
            loginStatus.font = .systemFont(ofSize: 12); loginStatus.textColor = .secondaryLabelColor
            add(card("Startup", views: [loginToggle, loginStatus, button("Login settings", #selector(openLoginSettings))]))
            add(card("Desktop control", subtitle: "Let your assistant use apps across your Mac. Set up once; access stays on until you pause it. Your Mac must be awake and unlocked.", views: [desktopStatus, row(button("Enable desktop control", #selector(enableDesktop)), button("Pause", #selector(stopDesktop))), row(button("Accessibility permission", #selector(desktopAccessibility)), button("Screen capture permission", #selector(desktopScreenPermission)))]))
            add(button("Advanced…", #selector(toggleAdvanced)))
            relay.stringValue = agent?.relay ?? ""
            let advanced = card("Connection settings", subtitle: "For self-hosted or development services. Production builds include their service address.", views: [row(field(relay, placeholder: "https://your-relay.example"), button("Save", #selector(saveRelay))), button("Open dashboard", #selector(dashboard)), button("Revoke pairing…", #selector(revoke)), button("I revoked in dashboard…", #selector(acknowledgeRevoke))])
            advancedView = advanced; advanced.isHidden = true; add(advanced)

        }
    }
    private func render() {
        guard let agent else { return }
        loginToggle.state = StartupSettings.enabled ? .on : .off
        loginStatus.stringValue = StartupSettings.message
        desktopStatus.stringValue = agent.executor.desktop.desktopWide ? "Desktop control enabled · apps across this Mac" : "Desktop control paused · enable once to get started"
        state.stringValue = agent.screenState == .unlocked ? "" : agent.screenState == .locked ? "Screen locked · information hidden" : "Session unavailable · actions paused"
        state.textColor = agent.screenState == .unlocked ? .systemGreen : .secondaryLabelColor
        state.isHidden = agent.screenState == .unlocked
        showFeedback(agent.lastCommand)
        volume.isEnabled = !agent.actionRunning && agent.screenState == .unlocked
        readButton?.title = agent.readingState ? "Reading…" : "Refresh"; readButton?.isEnabled = !agent.readingState
        controls.forEach { $0.isEnabled = !agent.actionRunning && agent.screenState == .unlocked }
        connection.stringValue = agent.pending ? RevocationState.warning : agent.status == "Unpaired" ? "" : agent.status
        codeLabel.stringValue = agent.code.isEmpty ? "" : "Code: " + agent.code
        pairingActions?.isHidden = agent.code.isEmpty || !agent.pairing
        connectButton?.title = !agent.connectionReady ? (agent.openingKeys ? "Connecting…" : "Connect") : agent.online ? "Connected" : agent.pairing ? "Waiting for approval…" : agent.token != nil ? "Reconnecting…" : "Connect"
        connectButton?.isEnabled = !agent.openingKeys && !agent.pairing && agent.token == nil && !agent.pending
        if agent.pending { advancedView?.isHidden = false }
        phoneHandoff?.isHidden = agent.token == nil || agent.pending
        let dashboardURL = (try? agent.dashboardOrigin().absoluteString) ?? ""
        if phoneURL != dashboardURL {
            phoneURL = dashboardURL
            phoneQR.image = nil
            if !dashboardURL.isEmpty {
                let filter = CIFilter.qrCodeGenerator()
                filter.message = Data(dashboardURL.utf8)
                if let output = filter.outputImage {
                    // White quiet zone keeps the code scannable in light and dark mode.
                    let padded = output.extent.insetBy(dx: -4, dy: -4)
                    let background = CIImage(color: CIColor.white).cropped(to: padded)
                    let code = output.composited(over: background)
                    let scale = CGAffineTransform(scaleX: 6, y: 6)
                    if let cg = CIContext().createCGImage(code.transformed(by: scale), from: padded.applying(scale)) {
                        phoneQR.image = NSImage(cgImage: cg, size: NSSize(width: 160, height: 160))
                    }
                }
            }
        }
        if qrCode != agent.code {
            qrCode = agent.code; pairingQR.image = nil
            pairingFallback?.isHidden = true
            pairingHelpButton?.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
            copyPairingButton?.title = "Copy code"
            if let url = agent.pairingURL() {
                let filter = CIFilter.qrCodeGenerator(); filter.message = Data(url.absoluteString.utf8)
                if let output = filter.outputImage, let cg = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 6, y: 6)), from: output.extent.applying(CGAffineTransform(scaleX: 6, y: 6))) {
                    pairingQR.image = NSImage(cgImage: cg, size: NSSize(width: 144, height: 144))
                }
            }
        }
        statusItem?.button?.toolTip = "Wand · " + agent.status
        if let value = agent.deviceState {
            if value["screen_locked"] == .bool(true) { showStatusRows([]); details.isHidden = false; details.stringValue = "Unlock on this Mac to use controls. Remote unlock is intentionally unavailable." }
            else {
                var readings: [(String, String)] = []
                let battery = value["battery"]?["percent"]?.number.map { "\(Int($0))%" } ?? "Unavailable"
                readings.append(("Battery", battery + (value["battery"]?["charging"] == .bool(true) ? " · Charging" : "")))
                if let system = value["system"] {
                    let gb: (Double) -> String = { String(format: "%.1f GB", $0 / 1e9) }
                    if let storage = system["storage"], let free = storage["available_bytes"]?.number, let total = storage["total_bytes"]?.number { readings.append(("Storage", "\(gb(free)) free of \(gb(total))")) }
                    if let memory = system["memory"], let used = memory["used_bytes"]?.number, let total = memory["total_bytes"]?.number { readings.append(("Memory", "About \(gb(used)) of \(gb(total)) in use")) }
                    if let seconds = system["uptime_seconds"]?.number {
                        let minutes = Int(seconds / 60), hours = minutes / 60, days = hours / 24
                        readings.append(("Uptime", days > 0 ? "\(days)d \(hours % 24)h" : hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes)m"))
                    }
                    readings.append(("Thermal", (system["thermal_state"]?.string ?? "Unavailable").capitalized))
                }
                readings.append(("Active app", value["frontmost_app"]?.string ?? "Unavailable"))
                let names = value["running_apps"]?.array?.compactMap(\.string) ?? []
                readings.append(("Open apps", names.prefix(8).joined(separator: ", ") + (names.count > 8 ? "…" : "")))
                details.isHidden = true
                showStatusRows(readings)

            }
        } else { showStatusRows([]); details.isHidden = false; details.stringValue = agent.readingState ? "Reading your Mac…" : "Refresh to see this Mac’s current state." }
        if selected == 1 { renderShortcuts() }
        if selected == 2, activitySnapshot != agent.lastCommand { refreshActivity() }
    }
    private func showStatusRows(_ readings: [(String, String)]) {
        let signature = readings.map { $0.0 + ":" + $0.1 }.joined(separator: "\n")
        guard signature != statusSignature else { return }; statusSignature = signature
        statusRows.arrangedSubviews.forEach { statusRows.removeArrangedSubview($0); $0.removeFromSuperview() }
        statusRows.orientation = .vertical; statusRows.alignment = .leading; statusRows.spacing = 12
        statusRows.isHidden = readings.isEmpty
        for (name, value) in readings {
            let title = NSTextField(labelWithString: name)
            title.font = .systemFont(ofSize: 12); title.textColor = .secondaryLabelColor
            title.widthAnchor.constraint(equalToConstant: 76).isActive = true
            let content = NSTextField(wrappingLabelWithString: value.isEmpty ? "None" : value)
            content.font = .systemFont(ofSize: 13, weight: .medium); content.isSelectable = true
            content.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let line = NSStackView(views: [title, content]); line.orientation = .horizontal; line.alignment = .firstBaseline; line.spacing = 12
            statusRows.addArrangedSubview(line); line.widthAnchor.constraint(equalTo: statusRows.widthAnchor).isActive = true
        }
    }
    private func showFeedback(_ message: String) {
        guard displayedCommand != message else { return }
        displayedCommand = message; feedbackTask?.cancel()
        let quiet = message == "None" || message.isEmpty || message.hasSuffix(" — succeeded")
        result.stringValue = quiet ? "" : message
        result.isHidden = quiet
        // Errors persist until the next action. Routine feedback fades after a moment.
        let brief = ["Application opened", "Website opened", "Audio muted", "Audio unmuted", "Volume changed", "Application quit", "Shortcut completed", "Playback toggled", "Skipped to next track", "Returned to previous track", "Completed", "Shortcut added to your allowlist"]
        if brief.contains(message) {
            feedbackTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                self?.result.stringValue = ""; self?.result.isHidden = true
            }
        }
    }
    private func renderShortcuts(force: Bool = false) {
        guard let agent, force || shortcutSnapshot != agent.shortcuts else { return }; shortcutSnapshot = agent.shortcuts
        shortcutsList.arrangedSubviews.forEach { shortcutsList.removeArrangedSubview($0); $0.removeFromSuperview() }
        if agent.shortcuts.isEmpty { shortcutsList.addArrangedSubview(label("No Shortcuts added yet. Start with a simple routine you know.", secondary: true)) }
        for (index, name) in agent.shortcuts.enumerated() {
            let run = actionButton("Run…", #selector(runShortcut(_:)), symbol: "play.fill"); run.tag = index
            let remove = button("Remove", #selector(removeShortcut(_:))); remove.tag = index
            shortcutsList.addArrangedSubview(row(label(name, weight: .medium), run, remove))
        }
    }
    private func confirm(_ title: String, detail: String, button: String) -> Bool {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        alert.addButton(withTitle: button); alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "Wand")
        let menu = NSMenu()
        for (title, action) in [("Open Wand", #selector(showWindow)), ("Pause desktop control", #selector(stopDesktop)), ("Visit getwand.app", #selector(websiteHome)), ("Quit Wand", #selector(quit))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }; statusItem?.menu = menu
    }
    @objc private func readState() { agent?.refreshDeviceState() }
    @objc private func refreshApps() {
        let selectedID = appPicker.selectedItem?.representedObject as? String
        appPicker.isEnabled = false
        Task { @MainActor in
        installedApps = await AppInventory.applications(refresh: true)
        appPicker.isEnabled = true
        appPicker.removeAllItems(); appPicker.addItem(withTitle: "Choose an app")
        for app in installedApps {
            let duplicate = installedApps.filter { $0.name == app.name }.count > 1
            appPicker.addItem(withTitle: app.name + (duplicate ? " · " + app.bundleID : ""))
            appPicker.lastItem?.representedObject = app.bundleID
        }
        appPicker.addItem(withTitle: "Other…"); appPicker.lastItem?.representedObject = "__manual"
        if let selectedID, let item = appPicker.itemArray.first(where: { $0.representedObject as? String == selectedID }) { appPicker.select(item) }
        appPicker.target = self; appPicker.action = #selector(appChoiceChanged)
        appPicker.setAccessibilityLabel("Installed apps, most recently opened first")
        appChoiceChanged()
        }
    }
    @objc private func appChoiceChanged() { appName.isHidden = appPicker.selectedItem?.representedObject as? String != "__manual" }
    private func chosenApp() -> (String, JSON)? {
        guard let id = appPicker.selectedItem?.representedObject as? String else { result.stringValue = "Choose an app first."; return nil }
        if id != "__manual" { return (installedApps.first(where: { $0.bundleID == id })?.name ?? id, .object(["bundle_id": .string(id)])) }
        let name = appName.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { result.stringValue = "Enter an app name or bundle ID."; return nil }
        let key = name.range(of: "^[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)+$", options: .regularExpression) != nil ? "bundle_id" : "app_name"
        return (name, .object([key: .string(name)]))
    }
    @objc private func openApp() { if let (_, params) = chosenApp() { agent?.runLocalAction("open_app", params: params) } }
    @objc private func quitApp() {
        guard let (name, params) = chosenApp(), confirm("Quit \(name)?", detail: "Wand will ask this app to quit gracefully. Any save dialog must be handled on this Mac.", button: "Quit app") else { return }
        agent?.runLocalAction("quit_app", params: params)
    }
    @objc private func playPause() { agent?.runLocalAction("media_play_pause") }
    @objc private func previous() { agent?.runLocalAction("media_previous") }
    @objc private func next() { agent?.runLocalAction("media_next") }
    @objc private func muteSound() { agent?.runLocalAction("mute") }
    @objc private func unmuteSound() { agent?.runLocalAction("unmute") }
    @objc private func setVolumeAction() { agent?.runLocalAction("set_volume", params: .object(["level": .number(volume.doubleValue.rounded())])) }
    @objc private func openWebsite() { agent?.runLocalAction("open_url", params: .object(["url": .string(website.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))])) }
    @objc private func enableDesktop() {
        guard confirm("Allow Muse-connected callers to control this Mac?", detail: "Desktop control covers applications across this Mac, including System Settings. Connected callers can read window contents, click, scroll and type, which can change files, send information or run code in capable apps. Content passes through Wand's relay. Access stays enabled across restarts and resumes after you unlock this Mac. Pause it anytime in Wand's menu. Password prompts and the lock screen remain yours to handle.", button: "Enable desktop control") else { return }
        agent?.executor.desktop.enableDesktop(); render()
    }
    @objc private func stopDesktop() { agent?.executor.desktop.stop(); render() }
    @objc private func desktopAccessibility() {
        guard confirm("Allow Wand to use Accessibility?", detail: "This lets Wand inspect buttons and fields and perform approved desktop interactions. macOS will ask you to enable Wand in Privacy & Security → Accessibility.", button: "Continue") else { return }
        agent?.executor.desktop.requestAccessibility()
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc private func desktopScreenPermission() {
        guard confirm("Allow window images?", detail: "Optional: desktop observations can include an image of the active app window. It is sent through the relay to the assistant, not saved in Wand's log. macOS requires Screen Recording permission.", button: "Continue") else { return }
        _ = CGRequestScreenCaptureAccess()
    }
    @objc private func lockMac() {
        if confirm("Lock this Mac?", detail: "You will need to unlock it on the Mac to continue using it.", button: "Lock") { agent?.runLocalAction("lock_screen", params: .object([:])) }
    }
    @objc private func sleepMac() {
        if confirm("Put this Mac to sleep?", detail: "Remote access stops until the Mac wakes. A sleeping Mac may not return a result.", button: "Sleep") { agent?.runLocalAction("sleep_mac", params: .object([:])) }
    }
    @objc private func focusOn() { agent?.runLocalAction("toggle_do_not_disturb", params: .object(["enabled": .bool(true)])) }
    @objc private func focusOff() { agent?.runLocalAction("toggle_do_not_disturb", params: .object(["enabled": .bool(false)])) }
    @objc private func cleanSafari() {
        let browser = cleanupBrowser.indexOfSelectedItem == 1 ? "Chrome" : "Safari"
        if confirm("Close unpinned \(browser) tabs?", detail: "This closes unpinned tabs in open \(browser) windows. Pinned tabs stay open. Unsaved pages may ask you to confirm in the browser.", button: "Close tabs") { agent?.runLocalAction("close_browser_tabs", params: .object(["browser": .string(browser.lowercased()), "keep_pinned": .bool(true)])) }
    }
    @objc private func pair() {
        guard let agent else { return }
        if !agent.connectionReady {
            Task { @MainActor in
                await agent.startConnections(allowInteraction: true)
                if agent.connectionReady { agent.pair() }
            }
        }
        else { agent.pair() }
    }
    @objc private func togglePairingHelp() {
        guard let fallback = pairingFallback else { return }
        fallback.isHidden.toggle()
        pairingHelpButton?.image = NSImage(systemSymbolName: fallback.isHidden ? "chevron.right" : "chevron.down", accessibilityDescription: nil)
    }
    @objc private func copyPairingCode() {
        guard let agent, agent.pairing, !agent.code.isEmpty, pairingFallback?.isHidden == false else { return }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(agent.code, forType: .string) { copyPairingButton?.title = "Copied" }
    }
    @objc private func continuePairing() { agent?.continuePairing() }
    @objc private func toggleAdvanced() { advancedView?.isHidden.toggle() }
    @objc private func saveRelay() {
        guard let agent, agent.token == nil, !agent.pairing else { agent?.status = "Disconnect before changing the service address."; return }
        let previous = agent.relay
        agent.relay = relay.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (try? agent.origin()) != nil else { agent.relay = previous; agent.status = "Enter a valid HTTPS service address."; return }
        UserDefaults.standard.set(agent.relay, forKey: "relay"); agent.status = "Service saved. You can connect now."
    }
    @objc private func cancelPairing() { agent?.cancelPairing() }
    @objc private func toggleStartAtLogin() {
        do { try StartupSettings.setEnabled(loginToggle.state == .on) }
        catch {
            let alert = NSAlert()
            alert.messageText = "Wand couldn’t change its startup setting."
            alert.informativeText = "Move Wand to Applications if needed, then check General → Login Items in System Settings."
            alert.runModal()
        }
        render()
    }
    @objc private func openLoginSettings() { StartupSettings.openSettings() }
    @objc private func sharePhoneLink(_ sender: NSButton) {
        guard let url = try? agent?.dashboardOrigin() else { return }
        let picker = NSSharingServicePicker(items: ["Open Wand on your phone and sign in with the same Google account to control your Mac.", url])
        phoneSharePicker = picker
        picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }
    @objc private func copyPhoneLink() {
        guard let url = try? agent?.dashboardOrigin() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
    @objc private func dashboard() { agent?.dashboard() }
    @objc private func revoke() { if confirm("Disconnect this Mac?", detail: "Remote commands will stop. If you are offline, you must also revoke in the dashboard.", button: "Revoke pairing") { agent?.revoke() } }
    @objc private func acknowledgeRevoke() { agent?.confirmDashboardRevocation() }
    @objc private func addShortcut() { agent?.saveShortcut(shortcut.stringValue); if agent?.shortcuts.contains(shortcut.stringValue) == true { shortcut.stringValue = "" }; render() }
    @objc private func openShortcuts() { agent?.runLocalAction("open_app", params: .object(["bundle_id": .string("com.apple.shortcuts")])) }
    @objc private func runShortcut(_ sender: NSButton) {
        guard let agent, agent.shortcuts.indices.contains(sender.tag) else { return }; let name = agent.shortcuts[sender.tag]
        if confirm("Run “\(name)” ?", detail: "This runs the approved Shortcut on this Mac. Its steps may change data or execute code.", button: "Run Shortcut") { agent.runLocalAction("run_shortcut", params: .object(["name": .string(name)])) }
    }
    @objc private func removeShortcut(_ sender: NSButton) { guard let agent, agent.shortcuts.indices.contains(sender.tag) else { return }; agent.removeShortcut(agent.shortcuts[sender.tag]); render() }
    @objc private func refreshActivity() {
        guard let agent else { return }; activitySnapshot = agent.lastCommand
        activityList.arrangedSubviews.forEach { activityList.removeArrangedSubview($0); $0.removeFromSuperview() }
        do {
            let file = agent.directory.appendingPathComponent("commands.jsonl")
            let data = FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : Data()
            let entries = try data.split(separator: 10).suffix(120).map { try JSON.parse(Data($0)) }.filter { $0["outcome"]?.string != "received" }.suffix(20).reversed()
            if entries.isEmpty { activityList.addArrangedSubview(label("Nothing here yet. Your next action will appear here.", secondary: true)) }
            for entry in entries {
                let name = (entry["action"]?.string ?? "Command").replacingOccurrences(of: "_", with: " ").capitalized
                let outcome = entry["outcome"]?.string ?? "Unknown"
                let time = entry["created_at"]?.string.flatMap(WireTime.parse).map { $0.formatted(date: .abbreviated, time: .shortened) } ?? ""
                activityList.addArrangedSubview(column([label(name, weight: .medium), label(time + " · " + (outcome == "succeeded" ? "Completed" : outcome.replacingOccurrences(of: "_", with: " ")), size: 12, secondary: true)], spacing: 3))
            }
        } catch { activityList.addArrangedSubview(label("The local log could not be read. Your commands have not been altered.", secondary: true)) }
    }
    @objc private func showLog() { if let agent { NSWorkspace.shared.activateFileViewerSelecting([agent.directory.appendingPathComponent("commands.jsonl")]) } }
    @objc private func websiteHome() { NSWorkspace.shared.open(URL(string: "https://getwand.app")!) }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}

private final class FlippedDocumentView: NSView { override var isFlipped: Bool { true } }
private final class CardView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 16, yRadius: 16)
        NSColor.controlBackgroundColor.setFill(); path.fill()
        
    }
}
