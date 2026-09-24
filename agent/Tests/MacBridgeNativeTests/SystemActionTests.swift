import XCTest
import MacBridgeCore
@testable import MacBridgeNative

final class SystemActionTests: XCTestCase {
    @MainActor func testConfirmedLockAndAlreadyLockedResultsMatchRelayContract() async throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let validator=try ContractValidator(schema:Data(contentsOf:root.appendingPathComponent("contracts/v1.schema.json")))
        var state=ScreenState.unlocked
        let fresh=try await SystemActions.confirmLock(readState:{ state },pause:{ state = .locked })
        XCTAssertEqual(fresh,.object(["already_locked":.bool(false)]))
        try validator.validate("LockResult",fresh)
        let repeated=try XCTUnwrap(CommandGate.lockedResult(action:"lock_screen",locked:true))
        XCTAssertEqual(repeated,.object(["already_locked":.bool(true)]))
        try validator.validate("LockResult",repeated)
        // A get_state result passed the native union but was rejected by the relay after locking.
        XCTAssertThrowsError(try validator.validate("LockResult",.object(["screen_locked":.bool(true)])))
    }
    @MainActor func testLockRequiresConfirmedLockedState() async {
        for state in [ScreenState.unlocked,.inactive,.unknown] {
            var checks=0,waits=0
            do {
                _ = try await SystemActions.confirmLock(readState:{ checks += 1; return state },pause:{ waits += 1 })
                XCTFail("Sending the shortcut is not proof the Mac locked")
            } catch let error as ContractError { XCTAssertEqual(error.code,"lock_not_confirmed") }
            catch { XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(checks,30)
            XCTAssertEqual(waits,29)
        }
    }
    @MainActor func testPinnedTabClassificationFailsClosed() {
        XCTAssertEqual(SystemActions.pinnedState("TabBarTab?isPinned=true&isActive=false"), true)
        XCTAssertEqual(SystemActions.pinnedState("TabBarTab?isPinned=false&isActive=true"), false)
        for identifier in ["TabBar?isPinned=false", "TabBarTab?isPinned=unknown", "TabBarTab?isActive=true", "TabBarTab?isPinned=false&isPinned=true"] {
            XCTAssertNil(SystemActions.pinnedState(identifier))
        }
    }
    @MainActor func testSafariClosureAcceptsConfirmedReplacementDespiteAXError() async throws {
        let original="original-start-page"
        var tabs=["pinned",original]
        var waits=0
        try await SystemActions.confirmSafariTabClosure(accepted:false,stillPresent:{
            tabs.contains(original)
        },pause:{
            waits += 1
            tabs=["pinned","replacement-start-page"]
        })
        XCTAssertEqual(waits,1)
        XCTAssertTrue(tabs.contains("pinned"))
        XCTAssertTrue(tabs.contains("replacement-start-page"))
    }
    @MainActor func testSafariClosureCannotAcceptAnUnchangedOriginalTab() async {
        for accepted in [false,true] {
            var checks=0,waits=0
            do {
                try await SystemActions.confirmSafariTabClosure(accepted:accepted,stillPresent:{
                    checks += 1
                    return true
                },pause:{ waits += 1 })
                XCTFail("A close request is not proof that the original tab disappeared")
            } catch let error as ContractError {
                XCTAssertEqual(error.code,accepted ? "browser_cleanup_pending_user_attention":"browser_cleanup_partial")
            } catch { XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(checks,10)
            XCTAssertEqual(waits,9)
        }
    }
    @MainActor func testSafariClosureNeverTreatsFailedObservationAsRemoval() async {
        do {
            try await SystemActions.confirmSafariTabClosure(accepted:true,stillPresent:{
                throw ContractError(code:"browser_window_unavailable")
            },pause:{ XCTFail("No retry should hide an unreadable browser") })
            XCTFail("An unreadable browser cannot prove closure")
        } catch let error as ContractError {
            XCTAssertEqual(error.code,"browser_window_unavailable")
        } catch { XCTFail("Unexpected error: \(error)") }
    }
}
