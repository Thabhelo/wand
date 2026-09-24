import AppKit

/// Standard shortcuts still need a main menu when the app lives in the menu bar.
@MainActor public enum ApplicationMenus {
    public static func install(on application: NSApplication = .shared) {
        let main = NSMenu()
        let app = submenu("Wand", in: main)
        add("About Wand", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), to: app)
        app.addItem(.separator())
        add("Hide Wand", action: #selector(NSApplication.hide(_:)), key: "h", to: app)
        add("Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option], to: app)
        add("Show All", action: #selector(NSApplication.unhideAllApplications(_:)), to: app)
        app.addItem(.separator())
        add("Quit Wand", action: #selector(NSApplication.terminate(_:)), key: "q", to: app)

        let edit = submenu("Edit", in: main)
        add("Undo", action: Selector(("undo:")), key: "z", to: edit)
        add("Redo", action: Selector(("redo:")), key: "z", modifiers: [.command, .shift], to: edit)
        edit.addItem(.separator())
        add("Cut", action: #selector(NSText.cut(_:)), key: "x", to: edit)
        add("Copy", action: #selector(NSText.copy(_:)), key: "c", to: edit)
        add("Paste", action: #selector(NSText.paste(_:)), key: "v", to: edit)
        add("Select All", action: #selector(NSText.selectAll(_:)), key: "a", to: edit)

        let window = submenu("Window", in: main)
        add("Close Window", action: #selector(NSWindow.performClose(_:)), key: "w", to: window)
        add("Minimize", action: #selector(NSWindow.performMiniaturize(_:)), key: "m", to: window)
        application.mainMenu = main
        application.windowsMenu = window
    }

    private static func submenu(_ title: String, in main: NSMenu) -> NSMenu {
        let menu = NSMenu(title: title)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        main.addItem(item)
        return menu
    }

    private static func add(_ title: String, action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = .command, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        // A nil target lets the focused field or window handle and validate the action.
        item.target = nil
        menu.addItem(item)
    }
}
