import XCTest
import ServiceManagement
@testable import MacBridgeNative
final class StartupPolicyTests: XCTestCase {
    func testMigrationRunsOnce() {
        XCTAssertNil(StartupPolicy.migration(loginItem: .enabled, attempted: true, migrated: true))
        XCTAssertNil(StartupPolicy.migration(loginItem: .notRegistered, attempted: false, migrated: true))
    }
    func testEnabledLoginItemMovesToTheAgent() {
        XCTAssertEqual(StartupPolicy.migration(loginItem: .enabled, attempted: true, migrated: false),
                       StartupPolicy.Migration(unregisterLoginItem: true, registerAgent: true))
    }
    func testLoginItemTheUserTurnedOffIsRemovedWithoutReplacement() {
        XCTAssertEqual(StartupPolicy.migration(loginItem: .requiresApproval, attempted: true, migrated: false),
                       StartupPolicy.Migration(unregisterLoginItem: true, registerAgent: false))
    }
    func testFreshInstallRegistersTheAgentOnlyOnTheFirstAttempt() {
        XCTAssertEqual(StartupPolicy.migration(loginItem: .notRegistered, attempted: false, migrated: false),
                       StartupPolicy.Migration(unregisterLoginItem: false, registerAgent: true))
        XCTAssertEqual(StartupPolicy.migration(loginItem: .notRegistered, attempted: true, migrated: false),
                       StartupPolicy.Migration(unregisterLoginItem: false, registerAgent: false))
        XCTAssertEqual(StartupPolicy.migration(loginItem: .notFound, attempted: true, migrated: false),
                       StartupPolicy.Migration(unregisterLoginItem: false, registerAgent: false))
    }
    func testOnlyTheLaunchdCopySurvivesADoubleStart() {
        XCTAssertEqual(StartupPolicy.launchDecision(managedByLaunchd: false, otherInstances: 0), .proceed)
        XCTAssertEqual(StartupPolicy.launchDecision(managedByLaunchd: true, otherInstances: 0), .proceed)
        XCTAssertEqual(StartupPolicy.launchDecision(managedByLaunchd: false, otherInstances: 1), .handOff)
        XCTAssertEqual(StartupPolicy.launchDecision(managedByLaunchd: true, otherInstances: 2), .takeOver)
    }
    func testMessagesAreDistinctAndMentionTheComeback() {
        let statuses: [SMAppService.Status] = [.enabled, .requiresApproval, .notRegistered, .notFound]
        let messages = statuses.map(StartupPolicy.message(for:))
        XCTAssertEqual(Set(messages).count, statuses.count)
        XCTAssertTrue(StartupPolicy.message(for: .enabled).contains("comes back"))
        XCTAssertTrue(StartupPolicy.message(for: .notRegistered).hasPrefix("Off."))
    }
    func testBundledLaunchAgentMatchesThePolicy() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("LaunchAgents").appendingPathComponent(StartupPolicy.agentPlistName))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["Label"] as? String, StartupPolicy.agentLabel)
        XCTAssertEqual(plist["BundleProgram"] as? String, "Contents/MacOS/MacBridge")
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        // A deliberate Quit must come back too, so KeepAlive is unconditional rather than SuccessfulExit-only.
        XCTAssertEqual(plist["KeepAlive"] as? Bool, true)
        XCTAssertEqual(plist["ProcessType"] as? String, "Interactive")
        XCTAssertEqual(plist["AssociatedBundleIdentifiers"] as? [String], ["local.macbridge.agent"])
        XCTAssertEqual((plist["EnvironmentVariables"] as? [String: String])?[StartupPolicy.keepAliveEnvironmentKey], "1")
        XCTAssertNil(plist["Program"]); XCTAssertNil(plist["ProgramArguments"])
    }
}
