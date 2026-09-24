import XCTest
import MacBridgeCore
@testable import MacBridgeNative

final class ObservationWindowTests: XCTestCase {
    @MainActor func window(pid: pid_t = 42, subrole: String = "AXStandardWindow", minimized: Bool? = false) -> DesktopControl.ObservationWindow {
        .init(processID:pid,role:"AXWindow",subrole:subrole,minimized:minimized,bounds:CGRect(x:10,y:10,width:640,height:480))
    }
    @MainActor func testFocusedAndMainWindowsTakePriorityWithoutGuessing() throws {
        let windows=[window(),window()]
        XCTAssertEqual(try DesktopControl.observationWindowIndex(windows,processID:42,focused:1,main:0),1)
        XCTAssertEqual(try DesktopControl.observationWindowIndex(windows,processID:42,focused:nil,main:0),0)
        XCTAssertThrowsError(try DesktopControl.observationWindowIndex(windows,processID:42,focused:nil,main:nil))
    }
    @MainActor func testFallbackSelectsOnlyUniqueSafeWindow() throws {
        let windows=[window(pid:99),window(minimized:true),window(),window(minimized:nil)]
        XCTAssertEqual(try DesktopControl.observationWindowIndex(windows,processID:42,focused:nil,main:nil),2)
        for unsafe in [window(pid:99),window(minimized:true),window(minimized:nil),window(subrole:"AXDialog")] {
            XCTAssertThrowsError(try DesktopControl.observationWindowIndex([unsafe],processID:42,focused:nil,main:0))
        }
    }
    @MainActor func testProtectedOrForeignFocusedWindowCannotFallBack() {
        for focused in [window(subrole:"AXSystemDialog"),window(pid:99)] {
            XCTAssertThrowsError(try DesktopControl.observationWindowIndex([focused,window()],processID:42,focused:0,main:1)) { error in
                XCTAssertEqual((error as? ContractError)?.code,"desktop_protected_ui")
            }
        }
        XCTAssertThrowsError(try DesktopControl.observationWindowIndex([window(),window(subrole:"AXSystemDialog")],processID:42,focused:nil,main:0))
    }
    @MainActor func testObservationWaitsForChosenWindowAndFrontmostApp() async throws {
        let chosen="chosen-window"
        var frontmost=99,focused=chosen,waits=0
        try await DesktopControl.confirmObservationFocus(matches:{ frontmost==42 && focused==chosen },pause:{
            waits += 1
            frontmost=42
            focused=waits==1 ? "another-window":chosen
        })
        XCTAssertEqual(waits,2)
    }
    @MainActor func testObservationNeverAcceptsUnconfirmedOrProtectedFocus() async {
        var checks=0,waits=0
        do {
            try await DesktopControl.confirmObservationFocus(matches:{ checks += 1; return false },pause:{ waits += 1 })
            XCTFail("Raising a window is not proof it is focused")
        } catch { XCTAssertEqual((error as? ContractError)?.code,"desktop_focus_changed") }
        XCTAssertEqual(checks,12)
        XCTAssertEqual(waits,11)
        do {
            try await DesktopControl.confirmObservationFocus(matches:{ throw ContractError(code:"desktop_protected_ui") },pause:{ XCTFail("Do not retry protected UI") })
            XCTFail("Protected focus cannot produce an observation")
        } catch { XCTAssertEqual((error as? ContractError)?.code,"desktop_protected_ui") }
    }
}
