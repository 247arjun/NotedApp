import AppKit
import Combine
import NotedKit

// MARK: - BucketBrowserWindowController

/// Lightweight read-only browser for the Archived and Trash buckets.
/// Loads its bucket on demand (not on app launch) and exposes restore /
/// permanent-delete (and Empty Trash) actions via a simple toolbar + context
/// menu. Notes can be opened by double-clicking; opening unarchives or
/// restores them first so the regular editor flow stays unchanged.
@MainActor
final class BucketBrowserWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    private let bucket: StorageBucket
    private weak var noteStore: NoteStore?
    private var notes: [NoteRecord] = []
    private var cancellable: AnyCancellable?

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "")

    init(noteStore: NoteStore, bucket: StorageBucket) {
        self.noteStore = noteStore
        self.bucket = bucket

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 460),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = bucket == .archived ? "Archived" : "Trash"
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("BucketBrowser.\(bucket.rawValue)")
        window.minSize = NSSize(width: 420, height: 280)
        super.init(window: window)

        buildUI()
        observeStore()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func showWindow() {
        reload()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note"))
        col.title = ""
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 56
        tableView.style = .sourceList
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.target = self
        tableView.menu = buildContextMenu()

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scrollView)

        emptyLabel.alignment = .center
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: content.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])

        // Empty-Trash toolbar button only on the trash window.
        if bucket == .trash {
            let toolbar = NSToolbar(identifier: "BucketBrowser.toolbar")
            toolbar.displayMode = .iconOnly
            toolbar.delegate = self
            window?.toolbar = toolbar
            window?.toolbarStyle = .unified
        }
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        if bucket == .archived {
            menu.addItem(NSMenuItem(title: "Restore to Notes", action: #selector(restoreSelected), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Move to Trash",    action: #selector(trashSelected),   keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "Restore",          action: #selector(restoreSelected),   keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Delete Forever…",  action: #selector(deleteForeverSelected), keyEquivalent: ""))
        }
        for item in menu.items { item.target = self }
        return menu
    }

    private func observeStore() {
        cancellable = noteStore?.objectWillChange
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
    }

    // MARK: - Data

    private func reload() {
        guard let store = noteStore else { return }
        let dict = (bucket == .archived) ? store.archivedNotes : store.trashedNotes
        if dict.isEmpty {
            // First open — fault them in
            _ = (bucket == .archived) ? store.loadArchived() : store.loadTrashed()
        }
        let source = (bucket == .archived) ? store.archivedNotes : store.trashedNotes
        notes = source.values.sorted { lhs, rhs in
            // Trash: most-recently trashed first; Archive: most-recently updated first.
            let l = (bucket == .trash) ? (lhs.trashedAt ?? lhs.updatedAt) : lhs.updatedAt
            let r = (bucket == .trash) ? (rhs.trashedAt ?? rhs.updatedAt) : rhs.updatedAt
            return l > r
        }
        emptyLabel.stringValue = bucket == .archived ? "No archived notes" : "Trash is empty"
        emptyLabel.isHidden = !notes.isEmpty
        scrollView.isHidden = notes.isEmpty
        tableView.reloadData()
    }

    private func selectedNote() -> NoteRecord? {
        let r = tableView.selectedRow
        guard r >= 0, r < notes.count else { return nil }
        return notes[r]
    }

    // MARK: - Actions

    @objc private func rowDoubleClicked() {
        guard let note = selectedNote(), let store = noteStore else { return }
        if bucket == .archived {
            store.unarchive(noteID: note.id)
        } else {
            store.restoreFromTrash(noteID: note.id)
        }
        AppCoordinator.shared.openNote(noteID: note.id)
        reload()
    }

    @objc private func restoreSelected() {
        guard let note = selectedNote(), let store = noteStore else { return }
        if bucket == .archived {
            store.unarchive(noteID: note.id)
        } else {
            store.restoreFromTrash(noteID: note.id)
        }
        reload()
    }

    @objc private func trashSelected() {
        guard let note = selectedNote() else { return }
        noteStore?.trash(noteID: note.id)
        reload()
    }

    @objc private func deleteForeverSelected() {
        guard let note = selectedNote(), let window else { return }
        let alert = NSAlert()
        alert.messageText = "Delete Forever?"
        alert.informativeText = "This note will be permanently removed. This action cannot be undone."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Delete Forever")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.noteStore?.deleteForever(noteID: note.id)
            self?.reload()
        }
    }

    @objc fileprivate func emptyTrashRequested() {
        guard bucket == .trash, !notes.isEmpty, let window else { return }
        let alert = NSAlert()
        alert.messageText = "Empty Trash?"
        alert.informativeText = "\(notes.count) note\(notes.count == 1 ? "" : "s") will be permanently deleted."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.noteStore?.emptyTrash()
            self?.reload()
        }
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { notes.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? BucketBrowserCellView)
            ?? BucketBrowserCellView(identifier: id)
        let note = notes[row]
        cell.configure(note: note, bucket: bucket)
        return cell
    }
}

// MARK: - Cell view

private final class BucketBrowserCellView: NSTableCellView {
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.translatesAutoresizingMaskIntoConstraints = false

        subtitleField.font = .systemFont(ofSize: 11)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.lineBreakMode = .byTruncatingTail
        subtitleField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleField)
        addSubview(subtitleField)

        NSLayoutConstraint.activate([
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            subtitleField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 2),
            subtitleField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            subtitleField.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
            subtitleField.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(note: NoteRecord, bucket: StorageBucket) {
        titleField.stringValue = note.title.isEmpty ? "Untitled" : note.title

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let when: String
        if bucket == .trash, let trashedAt = note.trashedAt {
            let interval = Date().timeIntervalSince(trashedAt)
            let daysLeft = max(0, 30 - Int(interval / 86_400))
            when = "Trashed \(formatter.string(from: trashedAt)) — \(daysLeft) day\(daysLeft == 1 ? "" : "s") left"
        } else {
            when = formatter.string(from: note.updatedAt)
        }
        let excerpt = note.bodyExcerpt
        subtitleField.stringValue = excerpt.isEmpty ? when : "\(when) — \(excerpt)"
    }
}

// MARK: - Toolbar (Trash only)

extension BucketBrowserWindowController: NSToolbarDelegate {
    private static let emptyTrashID = NSToolbarItem.Identifier("EmptyTrash")

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.emptyTrashID]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.emptyTrashID]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard id == Self.emptyTrashID else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.image = NSImage(systemSymbolName: "trash.slash", accessibilityDescription: "Empty Trash")
        item.label = "Empty Trash"
        item.target = self
        item.action = #selector(emptyTrashRequested)
        return item
    }
}
