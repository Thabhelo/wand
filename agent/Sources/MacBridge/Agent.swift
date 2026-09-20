import AppKit
import Foundation
import Combine
import MacBridgeCore
import MacBridgeNative

@MainActor final class Agent: ObservableObject {
    @Published var status = "Unpaired"
    @Published var code = ""
    @Published var relay = UserDefaults.standard.string(forKey: "relay") ?? (Bundle.main.object(forInfoDictionaryKey: "MacBridgeRelayOrigin") as? String ?? "")
    @Published var pairing = false
    @Published var online = false
    @Published var lastCommand = "None"
    @Published var screenState = ScreenState.unknown
    @Published var deviceState: JSON?
    @Published var readingState = false
    @Published var actionRunning = false
    var stateMonitor: Task<Void, Never>?
    @Published var pending = false
    @Published var shortcuts = UserDefaults.standard.stringArray(forKey: "shortcuts") ?? []
    let secrets = KeychainStore(service: "local.macbridge.agent")
    let directory: URL
    let validator: ContractValidator
    var ledger: DedupLedger
    var revocation: RevocationState
    let log: LocalForensicLog
    var socket: URLSessionWebSocketTask?
    var worker: Task<Void, Never>?
    var generation: UInt64 = 0
    var suspended = false
    var observers: [NSObjectProtocol] = []
    var token: String?
    var localServer: LocalHTTPServer?
    @Published var localPort: Int = 0
    let session = URLSession(configuration: .ephemeral)
    let executor = ActionExecutor()
    init() throws {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacBridge")
        guard let schema = Bundle.main.url(forResource: "v1.schema", withExtension: "json") else { throw ContractError(code: "schema_missing") }
        validator = try ContractValidator(schema: Data(contentsOf: schema))
        ledger = try DedupLedger(file: directory.appendingPathComponent("dedup.json"))
        revocation = try RevocationState(file: directory.appendingPathComponent("revocation.json"))
        log = LocalForensicLog(file: directory.appendingPathComponent("commands.jsonl"))
        pending = revocation.pending
        token = try secrets.read(account: "device-token")
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.suspend() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.suspended = false; self?.connect() }
            })
        }
        let savedPort = UserDefaults.standard.integer(forKey: "local-port")
        localPort = (49152...65535).contains(savedPort) ? savedPort : Int.random(in: 49152...65535)
        UserDefaults.standard.set(localPort, forKey: "local-port")
        let localToken = try secrets.read(account: "local-api-token") ?? KeychainStore.randomToken()
        try secrets.write(localToken, account: "local-api-token")
        localServer = try LocalHTTPServer(port: UInt16(localPort), token: localToken) { [weak self] value in
            guard let self else { return (503, .object([:])) }
            return await self.localCommand(value)
        }
        localServer?.start()
        screenState = LockStateReader.read()
        stateMonitor = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let next = LockStateReader.read()
                if next != self.screenState {
                    self.screenState = next
                    self.deviceState = nil
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        if pending { status = RevocationState.warning }
        else if token == nil, try secrets.read(account: "bootstrap-token") != nil {
            // Recover a crash after redemption without discarding revocation credentials.
            cancelPairing()
        } else { connect() }
    }
    func origin() throws -> URL {
        guard let u = URL(string: relay), u.scheme == "https", u.host != nil, u.user == nil, u.password == nil,
              u.query == nil, u.fragment == nil, u.path.isEmpty || u.path == "/" else { throw ContractError(code: "https_relay_required") }
        return u
    }
    func request(_ path: String, body: JSON, bearer: String? = nil) async throws -> JSON {
        var req = URLRequest(url: try origin().appendingPathComponent(path))
        req.httpMethod = "POST"; req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { req.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        req.httpBody = try body.data()
        let (data, response) = try await session.data(for: req)
        let result = try JSON.parse(data)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ContractError(code: result["error"]?["code"]?.string ?? "relay_request_failed")
        }
        return result
    }
    func dashboardOrigin() throws -> URL {
        let service = try origin()
        if service.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == (Bundle.main.object(forInfoDictionaryKey: "MacBridgeRelayOrigin") as? String ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/")),
           let configured = Bundle.main.object(forInfoDictionaryKey: "MacBridgeDashboardOrigin") as? String,
           let dashboard = URL(string: configured), dashboard.scheme == "https", dashboard.host != nil,
           dashboard.user == nil, dashboard.password == nil, dashboard.query == nil, dashboard.fragment == nil,
           dashboard.path.isEmpty || dashboard.path == "/" { return dashboard }
        return service
    }
    func pairingURL() -> URL? {
        guard !code.isEmpty, var url = try? URLComponents(url: dashboardOrigin(), resolvingAgainstBaseURL: false) else { return nil }
        // Only the short-lived human pairing code is handed off; device/bootstrap credentials never leave Keychain via URLs.
        url.fragment = "pair=" + code
        return url.url
    }
    func continuePairing() { if let url = pairingURL() { NSWorkspace.shared.open(url) } }
    func pair() {
        guard !pending, token == nil, !pairing else { return }
        do {
            if try secrets.read(account: "bootstrap-token") != nil { cancelPairing(); return }
        } catch { status = safeError(error); return }
        guard (try? origin()) != nil else { status = "Online setup is not available in this build yet. Local controls still work."; return }
        pairing = true
        worker?.cancel(); generation &+= 1
        let captured = generation
        worker = Task {
            do {
                _ = try origin(); UserDefaults.standard.set(relay, forKey: "relay")
                while !Task.isCancelled && generation == captured {
                    status = "Requesting a pairing code…"
                    let enrollment = try await request("v1/pairing/code", body: .object(["device_name": .string(Host.current().localizedName ?? "Mac"), "kind": .string("mac"), "agent_version": .string("0.9.1")]))
                    guard !Task.isCancelled, generation == captured else { return }
                    try validator.validate("PairingCodeResponse", enrollment)
                    guard let bootstrap = enrollment["bootstrap_token"]?.string, let expiryText = enrollment["expires_at"]?.string,
                          let expiry = WireTime.parse(expiryText), let deviceID = enrollment["device_id"]?.string else { throw ContractError(code: "invalid_pairing_response") }
                    try secrets.write(bootstrap, account: "bootstrap-token")
                    let candidate = try KeychainStore.randomToken()
                    try secrets.write(candidate, account: "pending-device-token")
                    code = enrollment["code"]?.string ?? ""; status = "Approve this Mac in your browser"
                    continuePairing()
                    while Date() < expiry && !Task.isCancelled && generation == captured {
                        do {
                            let redeemed = try await request("v1/pairing/redeem", body: .object(["device_token": .string(candidate)]), bearer: bootstrap)
                            try validator.validate("PairingRedeemResponse", redeemed)
                            guard !Task.isCancelled, generation == captured else { return }
                            guard redeemed["device_id"]?.string == deviceID else { throw ContractError(code: "device_identity_mismatch") }
                            // Persist public routing identity before promoting the secret.
                            UserDefaults.standard.set(deviceID, forKey: "device-id")
                            try secrets.write(candidate, account: "device-token")
                            try secrets.delete(account: "pending-device-token"); try secrets.delete(account: "bootstrap-token")
                            token = candidate; code = ""; pairing = false; connect(); return
                        } catch let e as ContractError where e.code == "pairing_expired" { break
                        } catch let e as ContractError where e.code == "pairing_pending" {
                            try await Task.sleep(for: .seconds(min(Double.random(in: 2.5...3.5), max(0, expiry.timeIntervalSinceNow))))
                        }
                    }
                    try secrets.delete(account: "pending-device-token"); try secrets.delete(account: "bootstrap-token")
                }
            } catch { if generation == captured { pairing = false; status = "Connection interrupted. Try connecting again." } }
        }
    }
    func cancelPairing() {
        guard token == nil else { return }
        worker?.cancel(); generation &+= 1; code = ""
        do { try revocation.begin(); pending = true } catch { status = safeError(error); return }
        status = "Cancelling connection…"
        Task {
            do {
                if let bootstrap = try secrets.read(account: "bootstrap-token") {
                    _ = try await request("v1/pairing/cancel", body: .object([:]), bearer: bootstrap)
                }
                try wipe(); status = "Unpaired"
            } catch { pairing = false; status = RevocationState.warning }
        }
    }
    func suspend() {
        suspended = true; online = false; pairing = false; generation &+= 1; worker?.cancel(); socket?.cancel(with: .goingAway, reason: nil); socket = nil; status = "Offline — session inactive"
    }
    func connect() {
        guard token != nil, !pending, !suspended else { return }
        worker?.cancel(); generation &+= 1
        let captured = generation
        worker = Task {
            var attempt = 0
            while !Task.isCancelled && generation == captured && token != nil && !pending {
                do { try await connected(captured); attempt = 0 }
                catch { if !Task.isCancelled { status = safeError(error) } }
                guard !Task.isCancelled, generation == captured, token != nil, !pending else { return }
                attempt = min(attempt + 1, 6)
                try? await Task.sleep(for: .seconds(Double.random(in: 0.5...min(60, pow(2, Double(attempt))))))
            }
        }
    }
    func send(_ value: JSON) async throws {
        try validator.validate("DeviceMessage", value)
        guard let socket else { throw ContractError(code: "device_offline") }
        try await socket.send(.string(String(decoding: try value.data(), as: UTF8.self)))
    }
    func connected(_ captured: UInt64) async throws {
        var components = URLComponents(url: try origin().appendingPathComponent("v1/ws/device"), resolvingAgainstBaseURL: false)!
        components.scheme = "wss"
        var request = URLRequest(url: components.url!)
        guard let deviceID = UserDefaults.standard.string(forKey: "device-id") else { throw ContractError(code: "device_identity_mismatch") }
        request.setValue(deviceID, forHTTPHeaderField: "X-Wand-Device-ID")
        let ws = session.webSocketTask(with: request); ws.maximumMessageSize = 65536
        socket = ws; ws.resume(); status = "Connecting…"
        guard let token else { return }
        try await send(envelope("hello", ["device_token": .string(token), "agent_version": .string("0.9.1"), "device_name": .string(Host.current().localizedName ?? "Mac"), "macos_version": .string(ProcessInfo.processInfo.operatingSystemVersionString.prefix(40).description)]))
        try await send(envelope("heartbeat"))
        let readinessTimeout = Task {
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            if generation == captured && !online { ws.cancel(with: .goingAway, reason: nil) }
        }
        let heartbeat = Task {
            do { while !Task.isCancelled { try await Task.sleep(for: .seconds(25)); try await send(envelope("heartbeat")) } }
            catch { ws.cancel(with: .goingAway, reason: nil) }
        }
        defer { readinessTimeout.cancel(); heartbeat.cancel(); ws.cancel(with: .goingAway, reason: nil); if generation == captured { socket = nil; online = false } }
        do {
            while !Task.isCancelled && generation == captured {
                let raw = try await ws.receive()
                guard generation == captured, !Task.isCancelled else { return }
                let data: Data
                switch raw { case .string(let text): data = Data(text.utf8); case .data(let bytes): data = bytes; @unknown default: throw ContractError(code: "invalid_message") }
                let message = try JSON.parse(data); try validator.validate("RelayMessage", message)
                if message["type"]?.string == "ready" {
                    guard message["device_id"]?.string == UserDefaults.standard.string(forKey: "device-id") else { throw ContractError(code: "device_identity_mismatch") }
                    online = true; status = "Mac connected"
                }
                if message["type"]?.string == "revoke" { try wipe(); return }
                if message["type"]?.string == "bye" { return }
                if message["type"]?.string == "command" { try await execute(message, generation: captured) }
            }
        } catch {
            if ws.closeCode.rawValue == 4003 { try wipe(); return }
            throw error
        }
    }
    func execute(_ command: JSON, generation captured: UInt64) async throws {
        guard let id = command["command_id"]?.string, let action = command["action"]?.string else { throw ContractError(code: "invalid_message") }
        do {
            guard generation == captured, !suspended, !pending else { throw ContractError(code: "session_changed") }
            try CommandGate.checkDeadline(command, now: Date()); try ledger.reserve(id, now: Date())
            try log.append(command: command, outcome: "received", now: Date())
            try await send(envelope("delivered", ["command_id": .string(id)]))
            guard generation == captured, !suspended, !pending else { throw ContractError(code: "session_changed") }
            try CommandGate.checkDeadline(command, now: Date())
            let data = try await executor.executeGuarded(action: action, params: command["params"]!, shortcuts: shortcuts)
            let safeData = try privacyChecked(data, action: action)
            guard generation == captured, !pending, !suspended else { throw ContractError(code: "session_changed") }
            try validator.validate("ActionResult", safeData)
            try log.append(command: command, outcome: "succeeded", now: Date())
            lastCommand = action + " — succeeded"
            try await send(envelope("result", ["command_id": .string(id), "ok": .bool(true), "data": safeData]))
        } catch {
            let outcome = safeError(error); lastCommand = action + " — " + outcome
            try log.append(command: command, outcome: outcome, now: Date())
            try await send(envelope("result", ["command_id": .string(id), "ok": .bool(false), "error_code": .string(outcome)]))
        }
    }
    func localCommand(_ request: JSON) async -> (Int, JSON) {
        do {
            try validator.validate("LocalCommandRequest", request)
            guard !suspended, !pending else { throw ContractError(code: "session_changed") }
            let command = envelope("command", ["command_id": .string(UUID().uuidString.lowercased()), "action": request["action"]!, "params": request["params"]!, "expires_at": .string(WireTime.text(Date().addingTimeInterval(15)))])
            try ledger.reserve(command["command_id"]!.string!, now: Date())
            try log.append(command: command, outcome: "received", now: Date())
            do {
                let data = try await executor.executeGuarded(action: request["action"]!.string!, params: request["params"]!, shortcuts: shortcuts)
                let safeData = try privacyChecked(data, action: request["action"]!.string!)
                try validator.validate("ActionResult", safeData)
                try log.append(command: command, outcome: "succeeded", now: Date())
                return (200, safeData)
            } catch { try log.append(command: command, outcome: safeError(error), now: Date()); throw error }
        } catch {
            let code = safeError(error)
            return (409, .object(["error": .object(["code": .string(code), "message": .string(code.replacingOccurrences(of: "_", with: " "))])]))
        }
    }
    func privacyChecked(_ data: JSON, action: String) throws -> JSON {
        guard action == "get_state" else { return data }
        // Recheck after collecting state; never disclose the snapshot if the screen locked
        // or ownership changed while it was being collected.
        if let guarded = try CommandGate.lockedResult(action: action, locked: LockStateReader.read().locked) { return guarded }
        return data
    }
    func runLocalAction(_ action: String, params: JSON = .object([:])) {
        guard !actionRunning else { return }
        actionRunning = true; lastCommand = "Working…"
        Task {
            defer { actionRunning = false }
            let (status, result) = await localCommand(.object(["action": .string(action), "params": params]))
            if status == 200 {
                let descriptions = ["open_app": "Application opened", "open_url": "Website opened", "mute": "Audio muted", "unmute": "Audio unmuted", "set_volume": "Volume changed", "quit_app": "Application quit", "run_shortcut": "Shortcut completed", "media_play_pause": "Playback toggled", "media_next": "Skipped to next track", "media_previous": "Returned to previous track"]
                lastCommand = descriptions[action] ?? "Completed"
            } else {
                lastCommand = friendlyError(result["error"]?["code"]?.string ?? "action_failed")
            }
        }
    }
    func refreshDeviceState() {
        guard !readingState else { return }
        readingState = true
        Task {
            defer { readingState = false }
            let (code, result) = await localCommand(.object(["action": .string("get_state"), "params": .object([:])]))
            if code == 200 { deviceState = result; lastCommand = "Mac status updated" }
            else { deviceState = nil; lastCommand = friendlyError(result["error"]?["code"]?.string ?? "action_failed") }
            screenState = LockStateReader.read()
        }
    }
    func revoke() {
        do { try revocation.begin(); pending = true; status = RevocationState.warning }
        catch { status = safeError(error); return }
        Task {
            let timeout = Task {
                try? await Task.sleep(for: .seconds(5))
                if pending { socket?.cancel(with: .goingAway, reason: nil) }
            }
            defer { timeout.cancel() }
            if socket != nil { try? await send(envelope("revoke_self")) }
            do { try secrets.delete(account: "device-token"); token = nil }
            catch { status = safeError(error) }
            try? await Task.sleep(for: .seconds(5))
            if pending { generation &+= 1; worker?.cancel(); socket?.cancel(with: .goingAway, reason: nil); socket = nil }
        }
    }
    func wipe() throws {
        try secrets.delete(account: "device-token"); try secrets.delete(account: "pending-device-token"); try secrets.delete(account: "bootstrap-token")
        token = nil; online = false; pairing = false; try revocation.acknowledge(); pending = false; code = ""; status = "Unpaired — revoked"
        UserDefaults.standard.removeObject(forKey: "device-id")
    }
    func confirmDashboardRevocation() {
        let alert = NSAlert(); alert.messageText = "Have you revoked this Mac in the web dashboard?"
        alert.informativeText = "Only confirm after the dashboard reports revocation. This clears the local warning; it cannot revoke the old server credential while offline."
        alert.addButton(withTitle: "I revoked it in the dashboard"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try wipe() } catch { status = safeError(error) }
    }
    func dashboard() { do { let u = try dashboardOrigin(); NSWorkspace.shared.open(u) } catch { status = "Enter your HTTPS relay address first." } }
    func saveShortcut(_ name: String) {
        guard !name.isEmpty, name.count <= 200, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { lastCommand = "Enter an exact Shortcut name, up to 200 characters, with no line breaks."; return }
        if !shortcuts.contains(where: { Array($0.utf8) == Array(name.utf8) }) { shortcuts.append(name) }
        UserDefaults.standard.set(shortcuts, forKey: "shortcuts"); lastCommand = "Shortcut added to your allowlist"
    }
    func removeShortcut(_ name: String) { shortcuts.removeAll { Array($0.utf8) == Array(name.utf8) }; UserDefaults.standard.set(shortcuts, forKey: "shortcuts") }
    func friendlyError(_ code: String) -> String {
        switch code {
        case "invalid_params", "invalid_message": return "Check the app name or website address, then try again."
        case "invalid_url": return "Enter a complete website address beginning with https:// or http://."
        case "app_not_found", "app_not_found_or_ambiguous": return "App not found. Enter its exact installed name, such as Calculator."
        case "device_locked": return "Unlock this Mac locally before running this action."
        case "lock_state_unknown": return "Wand cannot verify this session. Return to this Mac and try again."
        case "media_app_not_running": return "Open Music or Spotify first, then try playback again."
        case "automation_failed_or_permission_required", "permission_required": return "Allow Wand in System Settings → Privacy & Security → Automation, then retry."
        case "action_not_allowlisted": return "Add this exact Shortcut name in Shortcuts before running it."
        case "quit_pending_user_attention": return "The app is still open. Check it for a save dialog."
        case "action_timeout_outcome_unknown": return "This action took too long. Check the Mac before retrying; its outcome is unknown."
        default: return "Could not complete: " + code.replacingOccurrences(of: "_", with: " ")
        }
    }
    func safeError(_ error: Error) -> String { (error as? ContractError)?.code ?? "connection_or_storage_failed" }
}
