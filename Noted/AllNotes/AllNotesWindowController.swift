import AppKit
import NotedKit

// MARK: - AllNotesWindowController

/// Master-detail All Notes window — pure AppKit with Liquid Glass.
///
/// Toolbar layout:
/// ```
/// [ 🔍 Search ][ + ] |  .sidebarTrackingSeparator  |  .flexibleSpace  [ Pin 🎨 🗑 ✕ ]
///   ← sidebar area →                                   ← detail area (right-aligned) →
/// ```
@MainActor
final class AllNotesWindowController: NSWindowController, NSToolbarDelegate {

    private var listVC: AllNotesViewController!
    private var detailVC: NoteDetailViewController!
    private weak var noteStore: NoteStore?

    // MARK: - Toolbar Item IDs

    private static let toolbarID       = NSToolbar.Identifier("AllNotesToolbar")
    private static let searchItemID    = NSToolbarItem.Identifier("SearchItem")
    private static let createItemID    = NSToolbarItem.Identifier("CreateItem")
    private static let sortItemID      = NSToolbarItem.Identifier("SortItem")
    private static let folderItemID    = NSToolbarItem.Identifier("FolderItem")

    convenience init(
        noteStore: NoteStore,
        onOpenNote: @escaping (UUID) -> Void,
        onDeleteNote: @escaping (UUID) -> Void,
        onCreateNote: @escaping () -> Void,
        isWindowOpen: @escaping (UUID) -> Bool
    ) {
        // ── Sidebar (note list) ──
        let listVC = AllNotesViewController(noteStore: noteStore)
        listVC.onCreateNote = onCreateNote
        listVC.isWindowOpen = isWindowOpen
        listVC.onOpenNote = onOpenNote

        // ── Detail (note preview/editor) ──
        let detailVC = NoteDetailViewController(noteStore: noteStore)
        detailVC.onDeleteNote = onDeleteNote

        // Wire single-click → preview in detail pane
        listVC.onSelectNote = { [weak detailVC] noteID in
            detailVC?.showNote(id: noteID)
        }

        // Wire delete from list context menu
        listVC.onDeleteNote = { [weak detailVC] noteID in
            if detailVC?.currentNoteID == noteID {
                detailVC?.clearDetail()
            }
            onDeleteNote(noteID)
        }

        detailVC.onThemeChanged = { [weak listVC] _, _ in
            _ = listVC
        }

        detailVC.onWindowColorChanged = { [weak detailVC] color in
            guard let window = detailVC?.view.window else { return }
            window.backgroundColor = color ?? .windowBackgroundColor
        }

        // ── Split View Controller ──
        let splitVC = NSSplitViewController()

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: listVC)
        sidebarItem.minimumThickness = 240
        sidebarItem.maximumThickness = 400
        sidebarItem.canCollapse = false
        sidebarItem.holdingPriority = .defaultLow + 1

        let detailItem = NSSplitViewItem(viewController: detailVC)
        detailItem.minimumThickness = 320
        detailItem.canCollapse = false
        detailItem.titlebarSeparatorStyle = .none

        splitVC.addSplitViewItem(sidebarItem)
        splitVC.addSplitViewItem(detailItem)

        // ── Window ──
        let window = NSWindow(contentViewController: splitVC)
        window.title = "All Notes"
        window.subtitle = ""
        window.styleMask = [
            .titled, .closable, .resizable, .miniaturizable, .fullSizeContentView,
        ]
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified

        window.setContentSize(NSSize(width: 780, height: 520))
        window.minSize = NSSize(width: 600, height: 350)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("AllNotesWindow")
        window.tabbingMode = .disallowed

        self.init(window: window)
        self.listVC = listVC
        self.detailVC = detailVC
        self.noteStore = noteStore

        // ── Wire bucket-change side effects (post-init: self is valid). ──
        listVC.onBucketChanged = { [weak self] bucket in
            guard let self else { return }
            self.detailVC.clearDetail()
            self.refreshFolderToolbarItem()
            self.window?.title = bucket == .active ? "All Notes"
                                : bucket == .archived ? "Archived"
                                : "Trash"
        }

        detailVC.onRestoreNote = { [weak self] id in
            guard let self else { return }
            switch self.listVC.currentBucket {
            case .archived: self.noteStore?.unarchive(noteID: id)
            case .trash:    self.noteStore?.restoreFromTrash(noteID: id)
            case .active:   break
            }
            // Jump back to Active so the user can keep working with the note.
            self.setBucket(.active)
            self.detailVC.clearDetail()
            self.listVC.selectNote(id: id)
            self.detailVC.showNote(id: id)
        }

        detailVC.onMoveToTrash = { [weak self] id in
            self?.noteStore?.trash(noteID: id)
            self?.detailVC.clearDetail()
        }

        detailVC.onDeleteForever = { [weak self] id in
            self?.noteStore?.deleteForever(noteID: id)
            self?.detailVC.clearDetail()
        }
    }

    func showWindow() {
        // Install toolbar here — not in init — so self is fully initialized
        // before the toolbar queries its delegate for items.
        if window?.toolbar == nil {
            let toolbar = NSToolbar(identifier: Self.toolbarID)
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            toolbar.showsBaselineSeparator = false
            window?.toolbar = toolbar
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Switch the list to a given bucket. Safe to call before the window has
    /// been shown (used by AppCoordinator's Archive / Trash menu commands).
    func setBucket(_ bucket: StorageBucket) {
        listVC.setBucket(bucket)
        // onBucketChanged handles the rest (clear detail, update title, refresh icon).
    }

    func selectNote(id: UUID) {
        listVC.selectNote(id: id)
        detailVC.showNote(id: id)
    }

    /// Rebuilds the folder toolbar item so its label/icon reflects the
    /// currently-selected bucket and the popup menu's checkmark is correct.
    private func refreshFolderToolbarItem() {
        guard let toolbar = window?.toolbar,
              let item = toolbar.items.first(where: { $0.itemIdentifier == Self.folderItemID }) as? NSMenuToolbarItem else { return }
        configureFolderItem(item)
    }

    // MARK: - NSToolbarDelegate

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {

        case Self.folderItemID:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Folder"
            item.toolTip = "Switch folder"
            item.showsIndicator = true
            configureFolderItem(item)
            return item

        case Self.searchItemID:
            let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
            item.searchField = listVC.searchField
            item.preferredWidthForSearchField = 180
            return item

        case Self.createItemID:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "New Note"
            item.toolTip = "New Note"
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Note")?
                .withSymbolConfiguration(config)
            item.target = listVC
            item.action = #selector(AllNotesViewController.createClicked)
            return item

        case Self.sortItemID:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Sort"
            item.toolTip = "Sort notes"
            let sortConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            item.image = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: "Sort")?
                .withSymbolConfiguration(sortConfig)
            item.showsIndicator = true
            let sortMenu = NSMenu()
            for mode in NoteSortMode.allCases {
                let mi = NSMenuItem(title: mode.displayName, action: #selector(sortModeSelected(_:)), keyEquivalent: "")
                mi.target = self
                mi.tag = mode.rawValue
                mi.image = NSImage(systemSymbolName: mode.iconName, accessibilityDescription: nil)
                if mode == listVC.sortMode {
                    mi.state = .on
                }
                sortMenu.addItem(mi)
            }
            item.menu = sortMenu
            return item

        case NoteDetailViewController.controlGroupID:
            return detailVC.makeControlGroupItem()

        default:
            return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Self.folderItemID,
            Self.searchItemID,
            Self.createItemID,
            Self.sortItemID,
            .sidebarTrackingSeparator,
            .flexibleSpace,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Self.folderItemID,
            Self.searchItemID,
            Self.createItemID,
            Self.sortItemID,
            .sidebarTrackingSeparator,
            .flexibleSpace,
            .space,
            NoteDetailViewController.controlGroupID,
        ]
    }

    // MARK: - Folder Action

    private func configureFolderItem(_ item: NSMenuToolbarItem) {
        let current = listVC.currentBucket
        let symbolName: String
        switch current {
        case .active:   symbolName = "tray.2"
        case .archived: symbolName = "archivebox"
        case .trash:    symbolName = "trash"
        }
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Folder")?
            .withSymbolConfiguration(cfg)

        let menu = NSMenu()
        for bucket in [StorageBucket.active, .archived, .trash] {
            let title: String
            let sym: String
            switch bucket {
            case .active:   title = "Notes";    sym = "tray.2"
            case .archived: title = "Archived"; sym = "archivebox"
            case .trash:    title = "Trash";    sym = "trash"
            }
            let mi = NSMenuItem(title: title, action: #selector(folderItemSelected(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = bucket.rawValue
            mi.image = NSImage(systemSymbolName: sym, accessibilityDescription: nil)
            if bucket == current { mi.state = .on }
            menu.addItem(mi)
        }
        item.menu = menu
    }

    @objc private func folderItemSelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let bucket = StorageBucket(rawValue: raw) else { return }
        setBucket(bucket)
    }

    // MARK: - Sort Action

    @objc private func sortModeSelected(_ sender: NSMenuItem) {
        guard let mode = NoteSortMode(rawValue: sender.tag) else { return }
        listVC.sortMode = mode
        // Update menu checkmarks
        if let sortItem = window?.toolbar?.items.first(where: { $0.itemIdentifier == Self.sortItemID }) as? NSMenuToolbarItem {
            for mi in sortItem.menu.items {
                mi.state = mi.tag == mode.rawValue ? .on : .off
            }
        }
    }
}
