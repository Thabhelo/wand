import XCTest
@testable import MacBridgeNative
import MacBridgeCore
final class AppInventoryTests: XCTestCase {
    @MainActor func testRecencyThenUnknownAlphabeticalAndIdentifierTieBreak() {
        func entry(_ name:String,_ id:String,_ time:Double?) -> AppInventory.Entry {
            .init(name:name,bundleID:id,lastOpened:time.map { Date(timeIntervalSince1970:$0) },running:false,url:URL(fileURLWithPath:"/Applications/\(name).app"))
        }
        let result=AppInventory.ordered([entry("Zebra","a.z",nil),entry("Alpha","a.b",nil),entry("Recent","a.r",20),entry("Older","a.o",10),entry("Alpha","a.a",nil)])
        XCTAssertEqual(result.map(\.bundleID),["a.r","a.o","a.a","a.b","a.z"])
    }
    @MainActor func testAppListCannotDiscloseWhileLocked() {
        XCTAssertThrowsError(try CommandGate.lockedResult(action:"list_apps",locked:true))
        XCTAssertThrowsError(try CommandGate.lockedResult(action:"list_apps",locked:nil))
    }
    @MainActor func testInventoryHasUniqueIdentifiersBoundedPageAndNoPaths() async throws {
        let apps=await AppInventory.applications(refresh:true)
        XCTAssertFalse(apps.isEmpty)
        XCTAssertEqual(Set(apps.map(\.bundleID)).count,apps.count)
        let result=await AppInventory.page(offset:0)
        let data=try result.data()
        XCTAssertLessThan(data.count,60000)
        XCTAssertFalse(String(decoding:data,as:UTF8.self).contains("/Applications/"))
        let last=await AppInventory.page(offset:20000)
        XCTAssertEqual(last["apps"],.array([]));XCTAssertEqual(last["next_offset"],.null)
    }
}
