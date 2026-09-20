import Foundation
import MacBridgeCore

final class PolicyChecks {
    var directories: [URL] = []
    deinit { for url in directories { try? FileManager.default.removeItem(at: url) } }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MacBridgeTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directories.append(url)
        return url
    }
    func testExpiryToleranceAndFutureBound() throws {
        for offset in [-5.0, 0, 15, 20] {
            try CommandGate.checkDeadline(.object(["expires_at": .string(WireTime.text(now.addingTimeInterval(offset)))]), now: now)
        }
        for offset in [-5.001, 20.001] {
            try expectThrows(try CommandGate.checkDeadline(.object(["expires_at": .string(WireTime.text(now.addingTimeInterval(offset)))]), now: now))
        }
    }
    func testLockedPrivacyAndIdempotency() throws {
        try expectEqual(try CommandGate.lockedResult(action: "get_state", locked: true), .object(["screen_locked": .bool(true)]))
        try expectEqual(try CommandGate.lockedResult(action: "lock_screen", locked: true), .object(["already_locked": .bool(true)]))
        try expectThrows(try CommandGate.lockedResult(action: "get_state", locked: nil))
        try expectThrows(try CommandGate.lockedResult(action: "open_url", locked: true))
        try expectNil(try CommandGate.lockedResult(action: "lock_screen", locked: false))
    }
    func testDedupSurvivesRestartAndExpiresAtTenMinutes() throws {
        let path = try temporary().appendingPathComponent("ledger.json")
        let id = UUID().uuidString
        var ledger = try DedupLedger(file: path)
        try ledger.reserve(id, now: now)
        var restarted = try DedupLedger(file: path)
        try expectThrows(try restarted.reserve(id, now: now.addingTimeInterval(599)))
        try restarted.reserve(id, now: now.addingTimeInterval(600))
        let permissions = try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as! NSNumber
        try expectEqual(permissions.intValue, 0o600)
    }
    func testDedupCapacityEvictsOldest() throws {
        let path = try temporary().appendingPathComponent("ledger.json")
        let ids = (0..<10_000).map { _ in UUID().uuidString }
        // Seed an on-disk full ledger, then exercise the actual reservation path.
        let entries = ids.map { ["id": $0, "at": now.timeIntervalSinceReferenceDate] as [String: Any] }
        try JSONSerialization.data(withJSONObject: entries).write(to: path)
        var ledger = try DedupLedger(file: path)
        try ledger.reserve(UUID().uuidString, now: now)
        try ledger.reserve(ids[0], now: now)
        try expectThrows(try ledger.reserve(ids[9999], now: now))
        try expectEqual(try JSON.parse(Data(contentsOf: path)).array?.count, 10_000)
    }
    func testCorruptLedgerFailsClosed() throws {
        let path = try temporary().appendingPathComponent("ledger.json")
        try Data("not-json".utf8).write(to: path)
        try expectThrows(try DedupLedger(file: path))
    }
    func testRevocationPendingPersistsUntilAcknowledgment() throws {
        let path = try temporary().appendingPathComponent("revocation.json")
        var state = try RevocationState(file: path)
        try expectFalse(state.pending)
        try state.begin()
        var restarted = try RevocationState(file: path)
        try expectTrue(restarted.pending)
        let link = try state.dashboardLink(base: URL(string: "https://dashboard.example")!, deviceID: UUID())
        try expectNil(link.query)
        try expectThrows(try state.dashboardLink(base: URL(string: "http://dashboard.example")!, deviceID: UUID()))
        try restarted.acknowledge()
        try expectFalse(try RevocationState(file: path).pending)
    }
    func testPairingPollStopsAndJitterIsBounded() throws {
        let expiry = now.addingTimeInterval(10)
        try expectEqual(PairingSchedule.nextDelay(now: now, expiresAt: expiry, viewActive: true, sample: 0), 2.5)
        try expectEqual(PairingSchedule.nextDelay(now: now, expiresAt: expiry, viewActive: true, sample: 1), 3.5)
        try expectNil(PairingSchedule.nextDelay(now: expiry, expiresAt: expiry, viewActive: true, sample: 0.5))
        try expectNil(PairingSchedule.nextDelay(now: now, expiresAt: expiry, viewActive: false, sample: 0.5))
    }
    func testFullParamsOnlyInLocalLog() throws {
        let path = try temporary().appendingPathComponent("local.jsonl")
        let log = LocalForensicLog(file: path)
        let command: JSON = .object(["command_id": .string(UUID().uuidString), "action": .string("open_url"), "params": .object(["url": .string("https://example.com/private")])])
        try log.append(command: command, outcome: "received", now: now)
        let data = try Data(contentsOf: path)
        let entry = try JSON.parse(data)
        try expectEqual(entry["params"], command["params"])
        try expectNil(entry["device_token"])
        try expectNil(entry["data"])
        try log.append(command: command, outcome: "received", now: now.addingTimeInterval(90*86400))
        try expectEqual(try String(contentsOf: path, encoding: .utf8).split(separator: "\n").count, 1)
    }
}

struct CheckFailure: Error { let location: String }
func expectEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, file: String = #fileID, line: UInt = #line) throws {
    guard try lhs() == rhs() else { throw CheckFailure(location: "\(file):\(line)") }
}
func expectThrows<T>(_ body: @autoclosure () throws -> T, file: String = #fileID, line: UInt = #line) throws {
    do { _ = try body() } catch { return }
    throw CheckFailure(location: "\(file):\(line): expected failure")
}
func expectTrue(_ value: @autoclosure () throws -> Bool, file: String = #fileID, line: UInt = #line) throws { try expectEqual(value(), true, file: file, line: line) }
func expectFalse(_ value: @autoclosure () throws -> Bool, file: String = #fileID, line: UInt = #line) throws { try expectEqual(value(), false, file: file, line: line) }
func expectNil<T>(_ value: @autoclosure () throws -> T?, file: String = #fileID, line: UInt = #line) throws { try expectTrue(value() == nil, file: file, line: line) }

@main struct Main {
    static func main() throws {
        let checks = PolicyChecks()
        try checks.testExpiryToleranceAndFutureBound()
        print("PASS testExpiryToleranceAndFutureBound")
        try checks.testLockedPrivacyAndIdempotency()
        print("PASS testLockedPrivacyAndIdempotency")
        try checks.testDedupSurvivesRestartAndExpiresAtTenMinutes()
        print("PASS testDedupSurvivesRestartAndExpiresAtTenMinutes")
        try checks.testDedupCapacityEvictsOldest()
        print("PASS testDedupCapacityEvictsOldest")
        try checks.testCorruptLedgerFailsClosed()
        print("PASS testCorruptLedgerFailsClosed")
        try checks.testRevocationPendingPersistsUntilAcknowledgment()
        print("PASS testRevocationPendingPersistsUntilAcknowledgment")
        try checks.testPairingPollStopsAndJitterIsBounded()
        print("PASS testPairingPollStopsAndJitterIsBounded")
        try checks.testFullParamsOnlyInLocalLog()
        print("PASS testFullParamsOnlyInLocalLog")
    }
}
