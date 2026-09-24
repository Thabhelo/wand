import AppKit
import XCTest
@testable import MacBridgeNative

final class ApplicationMenuTests: XCTestCase {
    @MainActor func testStandardShortcutsPreserveResponderRoutingAndBackgroundPolicy() throws {
        let application = NSApplication.shared
        let oldMenu = application.mainMenu
        let oldWindowsMenu = application.windowsMenu
        let oldPolicy = application.activationPolicy()
        defer {
            application.mainMenu = oldMenu
            application.windowsMenu = oldWindowsMenu
        }
        ApplicationMenus.install(on: application)
        XCTAssertEqual(application.activationPolicy(), oldPolicy)
        let main = try XCTUnwrap(application.mainMenu)
        let edit = try XCTUnwrap(main.item(withTitle: "Edit")?.submenu)
        let expected: [(String, String, String, NSEvent.ModifierFlags)] = [
            ("Undo", "undo:", "z", .command),
            ("Redo", "redo:", "z", [.command, .shift]),
            ("Cut", "cut:", "x", .command),
            ("Copy", "copy:", "c", .command),
            ("Paste", "paste:", "v", .command),
            ("Select All", "selectAll:", "a", .command)
        ]
        for (title, action, key, modifiers) in expected {
            let item = try XCTUnwrap(edit.item(withTitle: title))
            XCTAssertEqual(item.action, Selector(action))
            XCTAssertEqual(item.keyEquivalent, key)
            XCTAssertEqual(item.keyEquivalentModifierMask, modifiers)
            XCTAssertNil(item.target, "The focused field must own editing actions")
        }
        let window = try XCTUnwrap(application.windowsMenu)
        XCTAssertEqual(window.item(withTitle: "Close Window")?.action, #selector(NSWindow.performClose(_:)))
        XCTAssertEqual(window.item(withTitle: "Close Window")?.keyEquivalent, "w")
        XCTAssertEqual(window.item(withTitle: "Minimize")?.keyEquivalent, "m")
        XCTAssertEqual(main.item(withTitle: "Wand")?.submenu?.item(withTitle: "Quit Wand")?.keyEquivalent, "q")
    }

    @MainActor func testCopyKeyEquivalentReachesTheResponder() throws {
        let application = NSApplication.shared
        let oldMenu = application.mainMenu
        let oldWindowsMenu = application.windowsMenu
        let oldResponder = application.nextResponder
        let responder = CopyResponder()
        defer {
            application.mainMenu = oldMenu
            application.windowsMenu = oldWindowsMenu
            application.nextResponder = oldResponder
        }
        application.nextResponder = responder
        ApplicationMenus.install(on: application)
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil,
            characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8))
        XCTAssertTrue(try XCTUnwrap(application.mainMenu).performKeyEquivalent(with: event))
        XCTAssertEqual(responder.copies, 1)
    }
}

@MainActor private final class CopyResponder: NSResponder {
    var copies = 0
    @objc func copy(_ sender: Any?) { copies += 1 }
}
