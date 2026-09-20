import AppKit
import SwiftUI
import Combine
import MacBridgeCore
import MacBridgeNative

@MainActor final class LabModel: ObservableObject {
    @Published var diagnostics = SessionDiagnostics.capture()
    @Published var status = "Ready for local checks"
    @Published var lastCommand = "None"
    @Published var shortcutName = ""
    @Published var allowlist: ShortcutAllowlist
    @Published var events: [String] = []
    @Published var recording = false
    @Published var revocationPending = false
    @Published var simulatedLocked = true
    @Published var selectedAction = "get_state"
    @Published var paramsText = "{}"
    @Published var logText = "No local command log yet."
    private var fence = SessionFence()
    private var observers: [NSObjectProtocol] = []
    private let preferences = UserDefaults.standard
    private let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacBridgeLab", isDirectory: true)

    init() {
        var loaded = ShortcutAllowlist()
        for name in UserDefaults.standard.stringArray(forKey: "shortcutAllowlist") ?? [] { try? loaded.add(name) }
        allowlist = loaded
        revocationPending = preferences.bool(forKey: "simulatedRevocationPending")
        let center = NSWorkspace.shared.notificationCenter
        let definitions: [(Notification.Name, String, Bool)] = [
            (NSWorkspace.willSleepNotification, "will_sleep", true),
            (NSWorkspace.didWakeNotification, "did_wake", false),
            (NSWorkspace.sessionDidResignActiveNotification, "session_resigned", true),
            (NSWorkspace.sessionDidBecomeActiveNotification, "session_activated", false)]
        for (name, label, suspend) in definitions {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sessionChanged(label, suspend: suspend) }
            })
        }
    }
    func refresh() { diagnostics = .capture(); status = "Read-only checks refreshed" }
    private func sessionChanged(_ label: String, suspend: Bool) {
        if suspend { fence.suspend() } else { fence.resume() }
        diagnostics = .capture()
        guard recording else { return }
        let line = "\(WireTime.text())  \(label)  generation=\(fence.generation)"
        events.append(line)
        if events.count > 500 { events.removeFirst(events.count - 500) }
        do { try PrivateFile.write(Data((events.joined(separator: "\n") + "\n").utf8), to: directory.appendingPathComponent("session-events.txt")) }
        catch { status = "Session event could not be saved; recording stopped"; recording = false }
    }
    func toggleRecording() {
        recording.toggle()
        status = recording ? "Recording session changes locally; no sleep or lock is triggered" : "Session recording stopped"
    }
    func saveShortcut() {
        do {
            try allowlist.add(shortcutName)
            preferences.set(allowlist.names, forKey: "shortcutAllowlist")
            shortcutName = ""
            status = "Saved to this test app’s allowlist; no Shortcut was run"
        } catch { status = "Use a nonempty name of at most 200 characters, without control characters" }
    }
    func removeShortcut(_ name: String) {
        allowlist.remove(name)
        preferences.set(allowlist.names, forKey: "shortcutAllowlist")
    }
    func keychainCheck() {
        // This is a user-initiated local storage test, not a pairing/device credential.
        let store = KeychainStore(service: "local.macbridge.lab.storage-test")
        let account = "roundtrip-" + UUID().uuidString
        do {
            let token = try KeychainStore.randomToken()
            try store.write(token, account: account)
            guard try store.read(account: account) == token else { throw ContractError(code: "keychain_mismatch") }
            try store.delete(account: account)
            guard try store.read(account: account) == nil else { throw ContractError(code: "keychain_delete_failed") }
            status = "Keychain check passed: generated, stored, read, and deleted; no token logged"
        } catch {
            // Attempt cleanup even when reading or verification fails.
            do { try store.delete(account: account) }
            catch { status = "Keychain check failed and cleanup needs attention"; return }
            status = "Keychain check failed; test item removed"
        }
    }
    func simulateRevocation() {
        revocationPending = true
        preferences.set(true, forKey: "simulatedRevocationPending")
        status = "Simulation paused until the simulated server acknowledges revocation"
    }
    func acknowledgeSimulatedRevocation() {
        revocationPending = false
        preferences.set(false, forKey: "simulatedRevocationPending")
        status = "Simulated revocation acknowledged; no real device pairing exists"
    }
    func simulate() {
        guard !revocationPending else { status = "revocation_pending"; return }
        do {
            guard let schema = Bundle.main.url(forResource: "v1.schema", withExtension: "json") else { throw ContractError(code: "contract_missing") }
            let validator = try ContractValidator(schema: Data(contentsOf: schema))
            guard paramsText.utf8.count <= 65536 else { throw ContractError(code: "message_too_large") }
            let params = try JSON.parse(Data(paramsText.utf8))
            let command = envelope("command", ["command_id": .string(UUID().uuidString.lowercased()), "action": .string(selectedAction), "params": params, "expires_at": .string(WireTime.text(Date().addingTimeInterval(15)))])
            try validator.validate("Command", command)
            let log = LocalForensicLog(file: directory.appendingPathComponent("simulated-commands.jsonl"))
            var ledger = try DedupLedger(file: directory.appendingPathComponent("simulated-dedup.json"))
            let generation = fence.generation
            try CommandGate.checkDeadline(command, now: Date())
            try ledger.reserve(command["command_id"]!.string!, now: Date())
            try log.append(command: command, outcome: "simulation_received", now: Date())
            var outcome: String
            do {
                guard fence.accepts(generation) else { throw ContractError(code: "session_inactive") }
                try CommandGate.checkDeadline(command, now: Date())
                if let result = try CommandGate.lockedResult(action: selectedAction, locked: simulatedLocked) {
                    try validator.validate("ActionResult", result)
                    outcome = String(data: try result.data(), encoding: .utf8)!
                } else if selectedAction == "run_shortcut", let name = params["name"]?.string, !allowlist.allows(name) {
                    throw ContractError(code: "action_not_allowlisted")
                } else {
                    // The test build has no executor. Never report a simulated OS action as succeeded.
                    throw ContractError(code: "live_actions_disabled")
                }
                try log.append(command: command, outcome: "simulation_succeeded", now: Date())
            } catch {
                outcome = (error as? ContractError)?.code ?? "simulation_failed"
                try log.append(command: command, outcome: outcome, now: Date())
            }
            lastCommand = "\(selectedAction) · simulation"
            status = "Simulation: \(outcome)"
            loadLog()
        } catch { status = (error as? ContractError)?.code ?? "Invalid JSON or local storage unavailable" }
    }
    func loadLog() {
        let path = directory.appendingPathComponent("simulated-commands.jsonl")
        guard FileManager.default.fileExists(atPath: path.path) else { logText = "No local command log yet."; return }
        do {
            let text = try String(contentsOf: path, encoding: .utf8)
            logText = text.split(separator: "\n").suffix(50).joined(separator: "\n")
        } catch { logText = "Could not read the local log." }
    }
    func exportReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MacBridge-Lab-Report.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            struct Report: Encodable { let diagnostics: SessionDiagnostics; let lifecycleEvents: [String] }
            let data = try JSONEncoder().encode(Report(diagnostics: diagnostics, lifecycleEvents: events))
            try data.write(to: url, options: .atomic)
            status = "Report saved locally; excludes command params, app names, URLs and tokens"
        } catch { status = "Could not save the report" }
    }
}

struct LabView: View {
    @ObservedObject var model: LabModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "desktopcomputer").font(.largeTitle).foregroundStyle(.blue)
                    VStack(alignment: .leading) {
                        Text("MacBridge Lab").font(.largeTitle.bold())
                        Text("Unpaired · Offline · Local test build").foregroundStyle(.secondary)
                    }
                }
                Text("Live Mac actions are disabled. Checks below never lock, sleep, quit apps, close tabs or run Shortcuts.")
                    .padding().frame(maxWidth: .infinity, alignment: .leading).background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                GroupBox("Read-only device checks") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("macOS", value: model.diagnostics.macOS)
                        LabeledContent("GUI session", value: model.diagnostics.guiSessionAvailable ? "Available" : "Unavailable")
                        LabeledContent("On console", value: model.diagnostics.sessionOnConsole.map { $0 ? "Yes" : "No" } ?? "Unknown")
                        LabeledContent("Screen lock detection", value: "Unverified — live actions blocked")
                        LabeledContent("Legacy CGSession executable", value: model.diagnostics.legacyLockExecutablePresent ? "Present; untested" : "Missing")
                        LabeledContent("Accessibility permission", value: model.diagnostics.accessibilityGranted ? "Granted" : "Not granted; not requested")
                        HStack {
                            Button("Refresh checks") { model.refresh() }
                            Button("Export safe report…") { model.exportReport() }
                        }
                    }.padding(8)
                }
                GroupBox("Session changes") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Record sleep/wake and user-switch notifications locally. Start this in the test account before a deliberate session test.")
                        Button(model.recording ? "Stop recording" : "Record session changes") { model.toggleRecording() }
                        if !model.events.isEmpty { Text(model.events.suffix(8).joined(separator: "\n")).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                GroupBox("Command simulation") {
                    VStack(alignment: .leading, spacing: 8) {
                        if model.revocationPending {
                            Label(RevocationState.warning, systemImage: "exclamationmark.shield").foregroundStyle(.orange)
                            Text("Simulated pending state. The production dashboard is not configured.").font(.caption)
                            Button("Simulate server acknowledgment") { model.acknowledgeSimulatedRevocation() }
                        }
                        Toggle("Simulate a locked Mac", isOn: $model.simulatedLocked).disabled(model.revocationPending)
                        Picker("Action", selection: $model.selectedAction) {
                            ForEach(["get_state", "lock_screen", "run_shortcut", "open_url", "close_browser_tabs"], id: \.self) { Text($0).tag($0) }
                        }.disabled(model.revocationPending)
                        TextField("Parameters as JSON", text: $model.paramsText).textFieldStyle(.roundedBorder).disabled(model.revocationPending)
                        HStack {
                            Button("Run simulation") { model.simulate() }.disabled(model.revocationPending)
                            Button("Simulate offline revoke") { model.simulateRevocation() }.disabled(model.revocationPending)
                        }
                        Text("Last command: \(model.lastCommand)").font(.caption)
                        DisclosureGroup("Local command log — full parameters stay on this Mac") {
                            Button("Refresh log") { model.loadLog() }
                            Text(model.logText).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(8)
                }
                GroupBox("Shortcut allowlist for this test build") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Names must match exactly. Saving a name here does not run it or authorize the contents of any other Shortcut.").font(.caption)
                        HStack {
                            TextField("Exact Shortcut name", text: $model.shortcutName).textFieldStyle(.roundedBorder)
                            Button("Add name") { model.saveShortcut() }
                        }
                        ForEach(model.allowlist.names, id: \.self) { name in
                            HStack { Text(name); Spacer(); Button("Remove") { model.removeShortcut(name) } }
                        }
                    }.padding(8)
                }
                GroupBox("Local credential storage check") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Creates a random test item in this user’s Keychain, verifies it, then deletes it. No account password is requested by MacBridge or saved in a file.").font(.caption)
                        Button("Test Keychain storage") { model.keychainCheck() }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                Text(model.status).font(.callout).textSelection(.enabled).accessibilityIdentifier("lab-status")
            }.padding(24)
        }.frame(minWidth: 650, idealWidth: 720, minHeight: 640, idealHeight: 840)
    }
}

@main struct MacBridgeLabApp: App {
    @StateObject private var model = LabModel()
    var body: some Scene {
        WindowGroup("MacBridge Lab", id: "lab") { LabView(model: model) }
            .defaultSize(width: 720, height: 840)
        MenuBarExtra("MacBridge Lab", systemImage: "desktopcomputer") {
            Text("MacBridge Lab — unpaired")
            Text(model.lastCommand)
            ShowLabButton()
            Divider()
            Button("Quit MacBridge Lab") { NSApplication.shared.terminate(nil) }
        }
    }
}
struct ShowLabButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View { Button("Show test panel") { NSApplication.shared.activate(); openWindow(id: "lab") } }
}
