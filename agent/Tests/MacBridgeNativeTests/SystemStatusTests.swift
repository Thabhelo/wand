import XCTest
@testable import MacBridgeNative
import MacBridgeCore
final class SystemStatusTests: XCTestCase {
    func testUsageClampsCountersAndOverflow() {
        XCTAssertEqual(SystemStatus.boundedUsage(total:1000,active:10,wired:20,compressed:5,pageSize:10),350)
        XCTAssertEqual(SystemStatus.boundedUsage(total:1000,active:200,wired:20,compressed:5,pageSize:10),1000)
        XCTAssertEqual(SystemStatus.boundedUsage(total:1000,active:UInt64.max,wired:20,compressed:5,pageSize:10),1000)
    }
    func testLiveSnapshotIsBoundedAndContainsNoDeviceIdentifiers() throws {
        let status=SystemStatus.read()
        XCTAssertNotNil(status["macos_version"]?.string)
        XCTAssertTrue(["normal","warm","hot","critical","unknown"].contains(status["thermal_state"]?.string ?? ""))
        if let memory=status["memory"],let total=memory["total_bytes"]?.number,let used=memory["used_bytes"]?.number { XCTAssertGreaterThan(total,0);XCTAssertGreaterThanOrEqual(used,0);XCTAssertLessThanOrEqual(used,total) }
        if let storage=status["storage"],let total=storage["total_bytes"]?.number,let free=storage["available_bytes"]?.number { XCTAssertGreaterThan(total,0);XCTAssertGreaterThanOrEqual(free,0);XCTAssertLessThanOrEqual(free,total) }
        if let seconds=status["uptime_seconds"]?.number { XCTAssertGreaterThanOrEqual(seconds,0) }
        XCTAssertLessThan(try status.data().count,1000)
        for key in ["serial_number","ip_address","hostname","files"] { XCTAssertNil(status[key]) }
    }
}
