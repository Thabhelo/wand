import XCTest
@testable import MacBridgeNative

final class SystemActionTests: XCTestCase {
    @MainActor func testPinnedTabClassificationFailsClosed() {
        XCTAssertEqual(SystemActions.pinnedState("TabBarTab?isPinned=true&isActive=false"), true)
        XCTAssertEqual(SystemActions.pinnedState("TabBarTab?isPinned=false&isActive=true"), false)
        for identifier in ["TabBar?isPinned=false", "TabBarTab?isPinned=unknown", "TabBarTab?isActive=true", "TabBarTab?isPinned=false&isPinned=true"] {
            XCTAssertNil(SystemActions.pinnedState(identifier))
        }
    }
}
