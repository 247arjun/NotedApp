import AppKit

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

    func selectNote(id: UUID) {
        listVC.selectNote(id: id)
        detailVC.showNote(id: id)
    }

    // MARK: - NSToolbarDelegate

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {

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

        case NoteDetailViewController.controlGroupID:
            return detailVC.makeControlGroupItem()

        default:
            return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Self.searchItemID,
            Self.createItemID,
            .sidebarTrackingSeparator,
            .flexibleSpace,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Self.searchItemID,
            Self.createItemID,
            .sidebarTrackingSeparator,
            .flexibleSpace,
            .space,
            NoteDetailViewController.controlGroupID,
        ]
    }
}
