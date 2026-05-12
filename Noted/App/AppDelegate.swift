import AppKit
import NotedKit

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var settingsWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
        AppCoordinator.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppCoordinator.shared.flushPendingSaves()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            AppCoordinator.shared.showAllNotes()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // Stay alive even if all windows are closed.
    }

    /// Menu shown when the user right-clicks (or two-finger taps) the app's
    /// Dock icon. "New Note" mirrors the File-menu / ⌘N command.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let newNote = menu.addItem(
            withTitle: "New Note",
            action: #selector(AppCoordinator.createNewNote),
            keyEquivalent: ""
        )
        newNote.target = AppCoordinator.shared
        newNote.image = NSImage(systemSymbolName: "square.and.pencil",
                                accessibilityDescription: "New Note")
        return menu
    }

    // MARK: - Main Menu

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Noted", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Noted", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Noted", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Note", action: #selector(AppCoordinator.createNewNote), keyEquivalent: "n").target = AppCoordinator.shared
        fileMenu.addItem(withTitle: "Duplicate Note", action: #selector(AppCoordinator.duplicateCurrentNote), keyEquivalent: "").target = AppCoordinator.shared
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Note", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let archiveItem = fileMenu.addItem(withTitle: "Archive Note", action: #selector(AppCoordinator.archiveCurrentNote), keyEquivalent: "A")
        archiveItem.keyEquivalentModifierMask = [.command, .shift, .control]
        archiveItem.target = AppCoordinator.shared
        let deleteItem = fileMenu.addItem(withTitle: "Move to Trash…", action: #selector(AppCoordinator.deleteCurrentNote), keyEquivalent: "\u{8}")
        deleteItem.target = AppCoordinator.shared
        deleteItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(.separator())
        let allNotesItem = fileMenu.addItem(withTitle: "All Notes", action: #selector(AppCoordinator.showAllNotes), keyEquivalent: "A")
        allNotesItem.keyEquivalentModifierMask = [.command, .shift]
        allNotesItem.target = AppCoordinator.shared
        let archiveBrowserItem = fileMenu.addItem(withTitle: "Archived Notes…", action: #selector(AppCoordinator.showArchive), keyEquivalent: "")
        archiveBrowserItem.target = AppCoordinator.shared
        let trashBrowserItem = fileMenu.addItem(withTitle: "Trash…", action: #selector(AppCoordinator.showTrash), keyEquivalent: "")
        trashBrowserItem.target = AppCoordinator.shared
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Export as Plain Text…", action: #selector(AppCoordinator.exportPlainText), keyEquivalent: "").target = AppCoordinator.shared
        fileMenu.addItem(withTitle: "Export as RTF…", action: #selector(AppCoordinator.exportRTF), keyEquivalent: "").target = AppCoordinator.shared
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let pasteMatch = editMenu.addItem(withTitle: "Paste and Match Style", action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "v")
        pasteMatch.keyEquivalentModifierMask = [.command, .option, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let findItem = editMenu.addItem(withTitle: "Find in Note…", action: #selector(AppCoordinator.performFindInNote(_:)), keyEquivalent: "f")
        findItem.target = AppCoordinator.shared
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Format menu
        let formatMenu = NSMenu(title: "Format")
        formatMenu.addItem(withTitle: "Bold", action: #selector(AppCoordinator.toggleBold(_:)), keyEquivalent: "b").target = AppCoordinator.shared
        formatMenu.addItem(withTitle: "Italic", action: #selector(AppCoordinator.toggleItalic(_:)), keyEquivalent: "i").target = AppCoordinator.shared
        formatMenu.addItem(withTitle: "Underline", action: #selector(AppCoordinator.toggleUnderline(_:)), keyEquivalent: "u").target = AppCoordinator.shared
        formatMenu.addItem(.separator())
        let incFont = formatMenu.addItem(withTitle: "Increase Font Size", action: #selector(AppCoordinator.increaseFontSize(_:)), keyEquivalent: "+")
        incFont.target = AppCoordinator.shared
        let decFont = formatMenu.addItem(withTitle: "Decrease Font Size", action: #selector(AppCoordinator.decreaseFontSize(_:)), keyEquivalent: "-")
        decFont.target = AppCoordinator.shared
        formatMenu.addItem(.separator())
        formatMenu.addItem(withTitle: "Align Left", action: #selector(AppCoordinator.alignTextLeft(_:)), keyEquivalent: "{").target = AppCoordinator.shared
        formatMenu.addItem(withTitle: "Align Center", action: #selector(AppCoordinator.alignTextCenter(_:)), keyEquivalent: "|").target = AppCoordinator.shared
        formatMenu.addItem(withTitle: "Align Right", action: #selector(AppCoordinator.alignTextRight(_:)), keyEquivalent: "}").target = AppCoordinator.shared
        formatMenu.addItem(.separator())
        formatMenu.addItem(withTitle: "Toggle Bullets", action: #selector(AppCoordinator.toggleBullets(_:)), keyEquivalent: "").target = AppCoordinator.shared
        formatMenu.addItem(.separator())
        formatMenu.addItem(withTitle: "Text Color…", action: #selector(AppCoordinator.showTextColor(_:)), keyEquivalent: "").target = AppCoordinator.shared
        let formatMenuItem = NSMenuItem()
        formatMenuItem.submenu = formatMenu
        mainMenu.addItem(formatMenuItem)

        // Note menu
        let noteMenu = NSMenu(title: "Note")
        noteMenu.addItem(withTitle: "Pin / Unpin", action: #selector(AppCoordinator.pinUnpinCurrentNote(_:)), keyEquivalent: "").target = AppCoordinator.shared
        noteMenu.addItem(withTitle: "Change Theme…", action: #selector(AppCoordinator.changeThemeCurrentNote(_:)), keyEquivalent: "").target = AppCoordinator.shared
        noteMenu.addItem(.separator())
        noteMenu.addItem(withTitle: "Bring to Front", action: #selector(AppCoordinator.bringNoteToFront(_:)), keyEquivalent: "").target = AppCoordinator.shared
        let noteMenuItem = NSMenuItem()
        noteMenuItem.submenu = noteMenu
        mainMenu.addItem(noteMenuItem)

        // Window menu
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        // Help menu
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "Noted Help", action: #selector(NSApplication.showHelp(_:)), keyEquivalent: "?")
        let helpMenuItem = NSMenuItem()
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        NSApp.helpMenu = helpMenu

        return mainMenu
    }

    @objc private func showSettings() {
        SettingsWindowController.shared.showWindow()
    }
}
