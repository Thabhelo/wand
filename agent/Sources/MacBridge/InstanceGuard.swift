import AppKit
import MacBridgeNative

/// Keeps one Wand per user session. The launchd copy wins, because launchd would restart it forever if it exited.
@MainActor enum InstanceGuard {
    struct Claim { let proceed: Bool; let showWindow: Bool }

    /// `proceed` is false when this copy should exit. `showWindow` is true when the copy it replaced was in front.
    static func claim() async -> Claim {
        // A copy started to replace a launchd copy waits for that copy to go before counting instances.
        if let pid = ProcessInfo.processInfo.environment[StartupPolicy.handoffEnvironmentKey].flatMap(Int32.init) {
            await wait(seconds: 10) { kill(pid, 0) != 0 }
        }
        let others = running()
        switch StartupPolicy.launchDecision(managedByLaunchd: StartupSettings.managedByLaunchd, otherInstances: others.count) {
        case .proceed: return Claim(proceed: true, showWindow: false)
        case .handOff:
            DistributedNotificationCenter.default().postNotificationName(Notification.Name(StartupPolicy.showWindowNotification), object: nil, userInfo: nil, deliverImmediately: true)
            return Claim(proceed: false, showWindow: false)
        case .takeOver:
            let wasInFront = others.contains { $0.isActive }
            for other in others { _ = other.terminate() }
            await wait(seconds: 10) { others.allSatisfy(\.isTerminated) }
            for other in others where !other.isTerminated { _ = other.forceTerminate() }
            await wait(seconds: 3) { others.allSatisfy(\.isTerminated) }
            return Claim(proceed: true, showWindow: wasInFront)
        }
    }

    private static func running() -> [NSRunningApplication] {
        // A bare development binary has no bundle identifier and never competes with the installed app.
        guard let identifier = Bundle.main.bundleIdentifier else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).filter { $0.processIdentifier != me }
    }

    private static func wait(seconds: Int, until done: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while !done() && ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(200)) }
    }
}
