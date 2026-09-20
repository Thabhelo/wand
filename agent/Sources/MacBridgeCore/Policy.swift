import Foundation

public enum PrivateFile {
    public static func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
        try data.write(to: url, options: .atomic)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public struct DedupLedger: Sendable {
    private struct Entry: Codable, Sendable { let id: String; let at: Date }
    private var entries: [Entry]
    private let file: URL
    public init(file: URL) throws {
        self.file = file
        if FileManager.default.fileExists(atPath: file.path) {
            entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: file))
            guard entries.count <= 10_000, entries.allSatisfy({ UUID(uuidString: $0.id) != nil }) else { throw ContractError(code: "invalid_ledger") }
        } else { entries = [] }
    }
    public mutating func reserve(_ id: String, now: Date) throws {
        guard UUID(uuidString: id) != nil else { throw ContractError(code: "invalid_message") }
        entries.removeAll { now.timeIntervalSince($0.at) >= 600 }
        guard !entries.contains(where: { $0.id == id }) else { throw ContractError(code: "duplicate_command") }
        entries.append(Entry(id: id, at: now))
        if entries.count > 10_000 { entries.removeFirst(entries.count - 10_000) }
        try PrivateFile.write(JSONEncoder().encode(entries), to: file)
    }
}

public struct LocalForensicLog: Sendable {
    private let file: URL
    public init(file: URL) { self.file = file }
    public func append(command: JSON, outcome: String, now: Date) throws {
        // Full action params are intentionally local. Never add hello/token/state payloads.
        let entry: JSON = .object(["command_id": command["command_id"]!, "action": command["action"]!,
                                   "params": command["params"]!, "outcome": .string(outcome), "created_at": .string(WireTime.text(now))])
        var lines: [Data] = []
        if FileManager.default.fileExists(atPath: file.path) {
            for bytes in try Data(contentsOf: file).split(separator: 10) {
                let data = Data(bytes)
                let old = try JSON.parse(data)
                guard let text = old["created_at"]?.string, let at = WireTime.parse(text) else { throw ContractError(code: "invalid_local_log") }
                if now.timeIntervalSince(at) < 90 * 86400 { lines.append(data) }
            }
        }
        lines.append(try entry.data())
        var size = lines.reduce(0) { $0 + $1.count + 1 }
        while size > 10 * 1024 * 1024, !lines.isEmpty { size -= lines.removeFirst().count + 1 }
        var output = Data()
        for line in lines { output.append(line); output.append(10) }
        try PrivateFile.write(output, to: file)
    }
}

public enum CommandGate {
    public static func checkDeadline(_ command: JSON, now: Date) throws {
        guard let text = command["expires_at"]?.string, let expiry = WireTime.parse(text) else { throw ContractError(code: "invalid_deadline") }
        if now.timeIntervalSince(expiry) > 5 { throw ContractError(code: "command_expired") }
        if expiry.timeIntervalSince(now) > 20 { throw ContractError(code: "invalid_deadline") }
    }
    /// nil means the executor may proceed after checking its own capability/allowlist.
    public static func lockedResult(action: String, locked: Bool?) throws -> JSON? {
        guard let locked else { throw ContractError(code: "lock_state_unknown") }
        if !locked { return nil }
        if action == "get_state" { return .object(["screen_locked": .bool(true)]) }
        if action == "lock_screen" { return .object(["already_locked": .bool(true)]) }
        throw ContractError(code: "device_locked")
    }
}

public struct RevocationState: Sendable {
    public static let warning = "Server-side revocation pending, complete it in the web dashboard"
    public private(set) var pending: Bool
    private let file: URL
    public init(file: URL) throws {
        self.file = file
        if FileManager.default.fileExists(atPath: file.path) {
            let value = try JSON.parse(Data(contentsOf: file))
            guard case .bool(let flag) = value["pending"] else { throw ContractError(code: "invalid_revocation_state") }
            pending = flag
        } else { pending = false }
    }
    public mutating func begin() throws { pending = true; try persist() }
    public mutating func acknowledge() throws { pending = false; try persist() }
    private func persist() throws { try PrivateFile.write(JSON.object(["pending": .bool(pending)]).data(), to: file) }
    public func dashboardLink(base: URL, deviceID: UUID) throws -> URL {
        guard base.scheme == "https", base.host != nil, base.user == nil, base.password == nil, base.query == nil, base.fragment == nil else { throw ContractError(code: "invalid_dashboard") }
        return base.appendingPathComponent("devices").appendingPathComponent(deviceID.uuidString.lowercased())
    }
}

public enum PairingSchedule {
    /// Caller injects a uniform sample in 0...1; no polling after the view closes/expiry.
    public static func nextDelay(now: Date, expiresAt: Date, viewActive: Bool, sample: Double) -> TimeInterval? {
        guard viewActive, expiresAt > now else { return nil }
        return min(2.5 + min(1, max(0, sample)), expiresAt.timeIntervalSince(now))
    }
}
