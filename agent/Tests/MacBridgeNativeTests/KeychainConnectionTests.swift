import XCTest
import MacBridgeCore
@testable import MacBridgeNative

final class KeychainConnectionTests: XCTestCase {
    func testPairedAndPendingConnectionsReadVaultExactlyOnceWithoutWrites() throws {
        for values in [["device-token": "device", "local-api-token": "local"],
                       ["bootstrap-token": "bootstrap", "pending-device-token": "pending", "local-api-token": "local"]] {
            var reads = 0
            let result = try KeychainStore.prepareConnection(load: { reads += 1; return values },
                readLegacy: { _ in XCTFail("Existing vault must not reopen legacy items"); return nil },
                save: { _ in XCTFail("Unchanged credentials must not be rewritten") },
                generate: { XCTFail("Existing local token must be preserved"); return "wrong" })
            XCTAssertEqual(reads, 1)
            XCTAssertEqual(result.local, "local")
            XCTAssertEqual(result.device, values["device-token"])
            XCTAssertEqual(result.hasBootstrap, values["bootstrap-token"] != nil)
        }
    }
    func testMissingLocalTokenIsPersistedAndOtherValuesSurvive() throws {
        var saved: [String:String]?
        _ = try KeychainStore.prepareConnection(load: { ["device-token":"device", "future":"preserve"] },
            readLegacy: { _ in XCTFail(); return nil }, save: { saved = $0 }, generate: { "new-local" })
        XCTAssertEqual(saved, ["device-token":"device", "future":"preserve", "local-api-token":"new-local"])
    }
    func testLegacyMigrationReadsEachItemOnceAndWritesOnce() throws {
        let old = ["device-token":"device", "local-api-token":"local", "bootstrap-token":"bootstrap", "pending-device-token":"pending"]
        var accounts: [String] = []; var writes = 0
        _ = try KeychainStore.prepareConnection(load: { nil }, readLegacy: { accounts.append($0); return old[$0] },
            save: { writes += 1; XCTAssertEqual($0,old) }, generate: { XCTFail(); return "wrong" })
        XCTAssertEqual(Set(accounts),Set(old.keys)); XCTAssertEqual(accounts.count,4); XCTAssertEqual(writes,1)
    }
    func testDeniedVaultReadDoesNotFallBackOrWrite() {
        XCTAssertThrowsError(try KeychainStore.prepareConnection(load: { throw ContractError(code:"denied") },
            readLegacy: { _ in XCTFail(); return nil }, save: { _ in XCTFail() }, generate: { XCTFail(); return "wrong" }))
    }
    func testDeniedLegacyReadDoesNotSavePartialMigration() {
        XCTAssertThrowsError(try KeychainStore.prepareConnection(load: { nil },
            readLegacy: { if $0 == "local-api-token" { throw ContractError(code:"denied") }; return "existing" },
            save: { _ in XCTFail() }, generate: { XCTFail(); return "wrong" }))
    }
    func testNewInstallationCreatesOneVaultWithoutRereading() throws {
        var reads = 0; var writes = 0
        let result = try KeychainStore.prepareConnection(load: { reads += 1; return nil },
            readLegacy: { _ in nil }, save: { writes += 1; XCTAssertEqual($0,["local-api-token":"new"]) }, generate: { "new" })
        XCTAssertEqual(reads,1); XCTAssertEqual(writes,1); XCTAssertNil(result.device)
    }
}
