import Foundation
import MacBridgeCore

/// Test-only loopback client. No Keychain, AppKit, AppleScript or Process action executor.
@MainActor final class Probe {
    let validator: ContractValidator
    var ledger: DedupLedger
    let localLog: LocalForensicLog
    var revocation: RevocationState
    var token: String?
    var socket: URLSessionWebSocketTask?
    init(schema: URL, directory: URL, token: String?) throws {
        validator = try ContractValidator(schema: Data(contentsOf: schema))
        ledger = try DedupLedger(file: directory.appendingPathComponent("dedup.json"))
        localLog = LocalForensicLog(file: directory.appendingPathComponent("local-log.jsonl"))
        revocation = try RevocationState(file: directory.appendingPathComponent("revocation.json"))
        self.token = token
    }
    func send(_ value: JSON) async throws {
        try validator.validate("DeviceMessage", value)
        guard let socket, let text = String(data: try value.data(), encoding: .utf8) else { throw ContractError(code: "disconnected") }
        try await socket.send(.string(text))
    }
    func handle(_ command: JSON) async throws {
        guard token != nil, !revocation.pending else { return }
        guard let cid = command["command_id"], let id = cid.string, let action = command["action"]?.string else { throw ContractError(code: "invalid_message") }
        var result: JSON
        do {
            try CommandGate.checkDeadline(command, now: Date())
            try ledger.reserve(id, now: Date())
            // Log before any execution; failure to persist prevents an action.
            try localLog.append(command: command, outcome: "received", now: Date())
            try CommandGate.checkDeadline(command, now: Date())
            // This peer simulates an already-locked Mac. Never inspects/changes host state.
            guard let data = try CommandGate.lockedResult(action: action, locked: true) else { throw ContractError(code: "action_unsupported") }
            try await send(envelope("delivered", ["command_id": cid]))
            try localLog.append(command: command, outcome: "succeeded", now: Date())
            result = envelope("result", ["command_id": cid, "ok": .bool(true), "data": data])
        } catch {
            let code = (error as? ContractError)?.code ?? "local_persistence_or_transport_failed"
            // Rejections retain full validated params locally too; never cloud log payloads.
            try localLog.append(command: command, outcome: code, now: Date())
            result = envelope("result", ["command_id": cid, "ok": .bool(false), "error_code": .string(code)])
        }
        try await send(result)
    }
    func run(url: URL, revokeSelf: Bool) async throws {
        guard url.scheme == "ws", url.host == "127.0.0.1", url.path == "/v1/ws/device", url.query == nil,
              url.user == nil, url.password == nil, url.fragment == nil else { throw ContractError(code: "probe_requires_loopback") }
        guard !revocation.pending else { token = nil; throw ContractError(code: "revocation_pending") }
        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = 65536
        socket = task
        task.resume()
        var heartbeat: Task<Void, Never>?
        var timeout: Task<Void, Never>?
        defer {
            heartbeat?.cancel(); timeout?.cancel()
            task.cancel(with: .normalClosure, reason: nil)
            session.invalidateAndCancel(); socket = nil
        }
        do {
            guard let token else { throw ContractError(code: "unpaired") }
            try await send(envelope("hello", ["device_token": .string(token), "agent_version": .string("0.1.0-probe"),
                                               "device_name": .string("Simulated Mac"), "macos_version": .string("26-test")]))
            if revokeSelf {
                try revocation.begin()
                // Send on the live authenticated connection; erase local credentials even if send fails.
                defer { self.token = nil }
                try await send(envelope("revoke_self"))
                timeout = Task {
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    task.cancel(with: .goingAway, reason: nil)
                }
            } else {
                try await send(envelope("heartbeat"))
                heartbeat = Task {
                    do {
                        while !Task.isCancelled {
                            try await Task.sleep(for: .seconds(25))
                            try await self.send(envelope("heartbeat"))
                        }
                    } catch { task.cancel(with: .goingAway, reason: nil) }
                }
            }
            while true {
                let received = try await task.receive()
                let data: Data
                switch received {
                case .string(let text): data = Data(text.utf8)
                case .data(let bytes): data = bytes
                @unknown default: throw ContractError(code: "unsupported_frame")
                }
                guard data.count <= 65536 else { throw ContractError(code: "message_too_large") }
                let value = try JSON.parse(data)
                do { try validator.validate("RelayMessage", value) }
                catch { task.cancel(with: .policyViolation, reason: nil); throw error }
                switch value["type"]?.string {
                case "ready": continue
                case "command": try await handle(value)
                case "revoke":
                    self.token = nil
                    try revocation.acknowledge()
                    // Relay owns the 4003 close handshake. Do not invalidate the URLSession
                    // immediately: that races the close frame and appears as an abnormal 1006.
                    timeout?.cancel()
                    timeout = Task {
                        do { try await Task.sleep(for: .seconds(5)) } catch { return }
                        task.cancel(with: .goingAway, reason: nil)
                    }
                case "bye": return
                default: throw ContractError(code: "invalid_message")
                }
            }
        } catch {
            if task.closeCode.rawValue == 4003 {
                self.token = nil
                try revocation.acknowledge()
                return
            }
            if revokeSelf { self.token = nil }
            throw error
        }
    }
}

@main struct Main {
    @MainActor static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            func arg(_ name: String) throws -> String {
                guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { throw ContractError(code: "missing_argument") }
                return args[index + 1]
            }
            let schema = URL(fileURLWithPath: try arg("--schema"))
            if args.contains("--validate-fixtures") {
                let validator = try ContractValidator(schema: Data(contentsOf: schema))
                let fixtures = try JSON.parse(Data(contentsOf: URL(fileURLWithPath: try arg("--validate-fixtures")))).array!
                for fixture in fixtures {
                    let valid = (try? validator.validate(fixture["model"]!.string!, fixture["value"]!)) != nil
                    guard fixture["valid"] == .bool(valid) else { throw ContractError(code: "fixture_mismatch_" + fixture["name"]!.string!) }
                }
                print("Validated \(fixtures.count) shared fixtures")
                return
            }
            guard let url = URL(string: try arg("--url")) else { throw ContractError(code: "invalid_url") }
            // Test token arrives on stdin, never in process arguments, URL, log, or disk.
            let probe = try Probe(schema: schema, directory: URL(fileURLWithPath: try arg("--data-dir")), token: readLine())
            try await probe.run(url: url, revokeSelf: args.contains("--revoke-self"))
            let summary = JSON.object(["token_present": .bool(probe.token != nil), "revocation_pending": .bool(probe.revocation.pending)])
            print(String(data: try summary.data(), encoding: .utf8)!)
        } catch {
            // No arbitrary error descriptions: transport errors can contain URLs/secrets.
            let code = (error as? ContractError)?.code ?? "probe_failed"
            FileHandle.standardError.write(Data((code + "\n").utf8))
            exit(1)
        }
    }
}
