import XCTest
import MacBridgeCore

final class CommandFeedbackTests: XCTestCase {
    func testDesktopPermissionFailureExplainsTheActualProblem() {
        let message = CommandFeedback.error("accessibility_permission_required")
        XCTAssertTrue(message.contains("macOS"))
        XCTAssertTrue(message.contains("Accessibility"))
        XCTAssertFalse(message.contains("_"))
        XCTAssertEqual(CommandFeedback.actionName("desktop_observe"), "Look at app")
        XCTAssertEqual(CommandFeedback.outcome("accessibility_permission_required"), message)
        XCTAssertNotEqual(message, CommandFeedback.error("desktop_permission_required"))
        XCTAssertNotEqual(message, CommandFeedback.error("screen_recording_permission_required"))
    }

    func testEveryCatalogActionHasAPresentationName() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("contracts/actions.json"))) as! [[String: Any]]
        for action in catalog.compactMap({ $0["name"] as? String }) {
            XCTAssertNotEqual(CommandFeedback.actionName(action), "Mac action", action)
            XCTAssertFalse(CommandFeedback.actionName(action).contains("_"), action)
        }
    }

    func testUnknownPeerValuesNeverBecomeUserFacingCopy() {
        let unexpected = "internal_error_with_private_path_or_server_text"
        XCTAssertEqual(CommandFeedback.actionName(unexpected), "Mac action")
        XCTAssertFalse(CommandFeedback.error(unexpected).contains(unexpected))
        XCTAssertFalse(CommandFeedback.outcome(unexpected).contains("_"))
        XCTAssertEqual(CommandFeedback.outcome("succeeded"), "Completed")
    }

    func testSuccessfulRepeatActionsReflectTheReturnedState() {
        XCTAssertEqual(CommandFeedback.success(action: "open_app", result: .object(["already_open": .bool(true), "focused": .bool(true)])), "App already open · brought to front")
        XCTAssertEqual(CommandFeedback.success(action: "open_app", result: .object(["already_open": .bool(true), "focused": .bool(false)])), "App was already open")
        XCTAssertEqual(CommandFeedback.success(action: "quit_app", result: .object(["already_closed": .bool(true)])), "App was already closed")
        XCTAssertEqual(CommandFeedback.success(action: "lock_screen", result: .object(["already_locked": .bool(true)])), "Mac was already locked")
        XCTAssertEqual(CommandFeedback.success(action: "get_state", result: .object(["screen_locked": .bool(true)])), "Mac is locked")
        XCTAssertEqual(CommandFeedback.success(action: "desktop_act", result: .object([:])), "Interaction sent")
    }

    func testUncertainResultsDoNotClaimSuccessOrEncourageBlindReplay() {
        XCTAssertTrue(CommandFeedback.error("action_timeout_outcome_unknown").contains("result is unknown"))
        XCTAssertTrue(CommandFeedback.error("browser_cleanup_partial").contains("Some tabs may have closed"))
        XCTAssertTrue(CommandFeedback.error("duplicate_command").contains("Check its result"))
    }
}
