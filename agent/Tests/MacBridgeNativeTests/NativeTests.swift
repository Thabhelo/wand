import XCTest
import MacBridgeCore
@testable import MacBridgeNative

final class NativeTests: XCTestCase {
    func testSuspensionAndWakeInvalidateOldCommands() {
        var fence = SessionFence()
        let before = fence.generation
        XCTAssertTrue(fence.accepts(before))
        fence.suspend()
        XCTAssertFalse(fence.accepts(before))
        XCTAssertFalse(fence.accepts(fence.generation))
        fence.resume()
        XCTAssertFalse(fence.accepts(before))
        XCTAssertTrue(fence.accepts(fence.generation))
    }
    func testExactShortcutAllowlist() throws {
        var list = ShortcutAllowlist()
        try list.add("Test notification")
        XCTAssertTrue(list.allows("Test notification"))
        XCTAssertFalse(list.allows("test notification"))
        XCTAssertFalse(list.allows("Test notification "))
        XCTAssertFalse(list.allows("Test notification; touch /tmp/pwn"))
        XCTAssertThrowsError(try list.add(""))
        XCTAssertThrowsError(try list.add("name\nother"))
        try list.add("Caf\u{00E9}")
        XCTAssertFalse(list.allows("Cafe\u{0301}"))
        list.remove("Test notification")
        XCTAssertFalse(list.allows("Test notification"))
    }
    func testGeneratedTokensAre256BitsAndURLSafe() throws {
        let tokens = try (0..<100).map { _ in try KeychainStore.randomToken() }
        XCTAssertEqual(Set(tokens).count, 100)
        for token in tokens {
            XCTAssertEqual(token.count, 43)
            XCTAssertNotNil(token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression))
        }
    }
    func testDiagnosticsDoNotDeclareAnUnlockedMac() async {
        let report = await SessionDiagnostics.capture()
        XCTAssertEqual(report.lockState, "unknown_unverified")
        XCTAssertFalse(report.liveActionsEnabled)
        let keys = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any]
        XCTAssertNil(keys?["running_apps"])
        XCTAssertNil(keys?["window_titles"])
        XCTAssertNil(keys?["urls"])
        XCTAssertNil(keys?["device_token"])
    }
}

final class LocalHTTPTests: XCTestCase, @unchecked Sendable {
    func testLoopbackBearerBoundary() async throws {
        let token = try KeychainStore.randomToken()
        let port = UInt16.random(in: 50000...62000)
        let server = try LocalHTTPServer(port: port, token: token) { request in (200, .object(["checked": .bool(true)])) }
        server.start(); defer { server.stop() }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        func call(_ bearer: String, origin: String? = nil) async throws -> Int {
            var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/commands")!)
            req.httpMethod = "POST"; req.timeoutInterval = 2
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
            if let origin { req.setValue(origin, forHTTPHeaderField: "Origin") }
            req.httpBody = Data("{\"action\":\"get_state\",\"params\":{}}".utf8)
            let (_, response) = try await session.data(for: req)
            return (response as! HTTPURLResponse).statusCode
        }
        // Listener startup is asynchronous. Retry connection failures only.
        var authenticated: Int?
        for _ in 0..<20 {
            do { authenticated = try await call(token); break }
            catch { try await Task.sleep(for: .milliseconds(50)) }
        }
        XCTAssertEqual(authenticated, 200)
        let unauthorized = try await call("wrong-token")
        XCTAssertEqual(unauthorized, 401)
        let crossOrigin = try await call(token, origin: "https://attacker.example")
        XCTAssertEqual(crossOrigin, 400)
    }
    @MainActor func testNativeExecutorRejectsUnsafeInputsBeforeExecution() async {
        let executor = ActionExecutor()
        for (action, params) in [("shell", JSON.object([:])), ("open_url", .object(["url": .string("file:///etc/passwd")])), ("run_shortcut", .object(["name": .string("$(touch /tmp/macbridge-never-created)")]))] {
            do { _ = try await executor.execute(action: action, params: params, shortcuts: []); XCTFail("Unsafe action executed") }
            catch { XCTAssertTrue(error is ContractError) }
        }
    }
}

final class LockStateTests: XCTestCase {
    let uid: UInt32 = 501
    func session(_ id: UInt32 = 501, console: Bool = true) -> [String: Any] {
        ["kCGSSessionUserIDKey": NSNumber(value:id), "kCGSSessionOnConsoleKey": console]
    }
    func testRequiresExplicitLockSignalAndOwnConsole() {
        let own = session()
        let open: [String: Any] = ["IOConsoleUsers": [own], "IOConsoleLocked": false]
        XCTAssertEqual(LockStateReader.evaluate(root: open, session: own, uid: uid), .unlocked)
        XCTAssertEqual(LockStateReader.evaluate(root: ["IOConsoleUsers": [own], "IOConsoleLocked": true], session: own, uid: uid), .locked)
        for invalid: Any in [NSNull(), "false", NSNumber(value:0)] {
            XCTAssertEqual(LockStateReader.evaluate(root: ["IOConsoleUsers": [own], "IOConsoleLocked": invalid], session: own, uid: uid), .unknown)
        }
        XCTAssertEqual(LockStateReader.evaluate(root: ["IOConsoleUsers": [own]], session: own, uid: uid), .unknown)
        XCTAssertEqual(LockStateReader.evaluate(root: open, session: nil, uid: uid), .unknown)
        XCTAssertEqual(LockStateReader.evaluate(root: open, session: session(console:false), uid: uid), .inactive)
        XCTAssertEqual(LockStateReader.evaluate(root: open, session: session(502), uid: uid), .unknown)
        XCTAssertEqual(LockStateReader.evaluate(root: ["IOConsoleUsers": [own,session(502)], "IOConsoleLocked": false], session: own, uid: uid), .unknown)
        var conflicting = own; conflicting["CGSSessionScreenIsLocked"] = true
        XCTAssertEqual(LockStateReader.evaluate(root: ["IOConsoleUsers": [conflicting], "IOConsoleLocked": false], session: own, uid: uid), .unknown)
    }
}

final class LiveReadOnlyTests: XCTestCase {
    @MainActor func testRealStateReadUsesProductionGuardAndSchema() async throws {
        guard LockStateReader.read() == .unlocked else { throw XCTSkip("Requires the current user's active unlocked session") }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let validator = try ContractValidator(schema: Data(contentsOf: root.appendingPathComponent("contracts/v1.schema.json")))
        let result = try await ActionExecutor().executeGuarded(action: "get_state", params: .object([:]), shortcuts: [])
        try validator.validate("State", result)
        XCTAssertNotNil(result["screen_locked"])
        // Do not print or persist actual app names or other state payload contents.
    }
}

final class NowPlayingTests: XCTestCase {
    @MainActor func testMetadataIsBoundedAndRequiresKnownSource() {
        XCTAssertEqual(NowPlayingReader.normalized(title: "Track", artist: "Artist", source: "Browser"), .null)
        XCTAssertEqual(NowPlayingReader.normalized(title: nil, artist: "Artist", source: "Music"), .null)
        XCTAssertEqual(NowPlayingReader.normalized(title: "", artist: "Artist", source: "Spotify"), .null)
        let state = NowPlayingReader.normalized(title: String(repeating: "a", count: 700), artist: "Artist", source: "Music")
        XCTAssertEqual(state["title"]?.string?.count, 500)
        XCTAssertEqual(state["source_app"]?.string, "Music")
    }
}
