import AppKit

// MARK: - AllNotesWindowController

/// Master-detail All Notes window — pure AppKit with Liquid Glass.
///
/// Layout:
/// ```
/// ┌───────────────┬──────────────────────────────────┐
/// │  Sidebar       │  Detail (NoteContentView)        │
/// │  (note list)   │  ← full note editor/preview     │
/// │  NSTableView   │  with header controls            │
/// │                │                                  │
/// └───────────────┴──────────────────────────────────┘
/// ```
///
/// - Single click selects → shows note in detail pane (editable preview).
/// - Double click opens note in standalone floating window.
/// - NSSplitViewController sidebar gets Liquid Glass automatically on macOS 26.
@MainActor
final class AllNotesWindowController: NSWindowController {

    private var listVC: AllNotesViewController!
    private var detailVC: NoteDetailViewController!
    private weak var noteStore: NoteStore?

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
        listVC.onOpenNote = onOpenNote          // double-click → standalone window

        // ── Detail (note preview/editor) ──
        let detailVC = NoteDetailViewController(noteStore: noteStore)
        detailVC.onDeleteNote = onDeleteNote

        // Wire single-click → preview in detail pane
        listVC.onSelectNote = { [weak detailVC] noteID in
            detailVC?.showNote(id: noteID)
        }

        // Wire delete from list context menu
        listVC.onDeleteNote = { [weak detailVC] noteID in
            // If the deleted note is currently previewed, clear it
            if detailVC?.currentNoteID == noteID {
                detailVC?.clearDetail()
            }
            onDeleteNote(noteID)
        }

        // When theme changes in detail, refresh the list row
        detailVC.onThemeChanged = { [weak listVC] _, _ in
            _ = listVC  // NoteStore @Published triggers list reload
        }

        // Tint the entire window background with the selected note's theme color.
        // The sidebar's behindWindow blending will pick up this tint, creating
        // a full-window colored glass effect.
        detailVC.onWindowColorChanged = { [weak detailVC] color in
            guard let window = detailVC?.view.window else { return }
            if let color {
                window.backgroundColor = color
            } else {
                window.backgroundColor = .windowBackgroundColor
            }
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
            .titled,
            .closable,
            .resizable,
            .miniaturizable,
            .fullSizeContentView,
        ]
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified

        // An NSToolbar is required for the sidebar to get its Liquid Glass
        // treatment and the system sidebar-toggle button.
        let toolbar = NSToolbar(identifier: "AllNotesToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar

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
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Select a note in the list and show it in detail (e.g. after create).
    func selectNote(id: UUID) {
        listVC.selectNote(id: id)
        detailVC.showNote(id: id)
    }
}
