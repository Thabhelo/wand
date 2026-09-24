import XCTest
@testable import MacBridgeNative
final class DeviceCapabilityTests: XCTestCase {
    @MainActor func testAdvertisedActionsMatchTheClosedCatalog() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let entries = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("contracts/actions.json"))) as! [[String: Any]]
        XCTAssertEqual(Set(DeviceCapabilityReport.actions), Set(entries.compactMap { $0["name"] as? String }))
        XCTAssertFalse(DeviceCapabilityReport.actions.contains("shell"))
        XCTAssertFalse(DeviceCapabilityReport.actions.contains("unlock"))
    }
}
