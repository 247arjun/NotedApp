import AppKit
import NotedKit
import Combine

// MARK: - NoteSortMode

enum NoteSortMode: Int, CaseIterable {
    case updatedDate = 0
    case createdDate = 1
    case titleAZ = 2
    case titleZA = 3
    case manual = 4

    var displayName: String {
        switch self {
        case .updatedDate: return "Date Modified"
        case .createdDate: return "Date Created"
        case .titleAZ:     return "Title (A→Z)"
        case .titleZA:     return "Title (Z→A)"
        case .manual:      return "Manual"
        }
    }

    var iconName: String {
        switch self {
        case .updatedDate: return "clock"
        case .createdDate: return "calendar"
        case .titleAZ:     return "textformat.abc"
        case .titleZA:     return "textformat.abc"
        case .manual:      return "hand.draw"
        }
    }
}

// MARK: - Drag type

private let noteRowDragType = NSPasteboard.PasteboardType("com.arjun.Noted.note-row")

// MARK: - AllNotesViewController

final class AllNotesViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

    // MARK: - Callbacks

    var onSelectNote: ((UUID) -> Void)?
    var onOpenNote: ((UUID) -> Void)?
    var onDeleteNote: ((UUID) -> Void)?
    var onCreateNote: (() -> Void)?
    var isWindowOpen: ((UUID) -> Bool)?

    // MARK: - Data

    private weak var noteStore: NoteStore?
    private var cancellable: AnyCancellable?
    private var searchText: String = ""

    /// Pinned notes (section 0)
    private var pinnedNotes: [NoteRecord] = []
    /// Unpinned notes (section 1)
    private var otherNotes: [NoteRecord] = []

    /// Flat list for table view (section headers are nil entries).
    /// Layout: [pinned-header?, pinned..., other-header?, other...]
    private enum RowItem {
        case sectionHeader(String)
        case note(NoteRecord)
    }
    private var rows: [RowItem] = []

    var sortMode: NoteSortMode = .updatedDate {
        didSet { reloadData() }
    }

    // MARK: - Subviews

    let searchField = NSSearchField()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "No notes yet")

    // MARK: - Identifiers

    private static let noteColumnID = NSUserInterfaceItemIdentifier("NoteColumn")

    // MARK: - Init

    init(noteStore: NoteStore) {
        self.noteStore = noteStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 500))

        searchField.placeholderString = "Search notes…"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true

        let column = NSTableColumn(identifier: Self.noteColumnID)
        column.title = ""
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 68
        tableView.style = .sourceList
        tableView.allowsMultipleSelection = false
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.target = self
        tableView.menu = buildContextMenu()
        tableView.backgroundColor = .clear

        // Drag & drop
        tableView.registerForDraggedTypes([noteRowDragType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])

        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadData()

        cancellable = noteStore?.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadData()
            }
    }

    // MARK: - Data

    private func reloadData() {
        guard let store = noteStore else { return }
        var all = Array(store.notes.values.filter { !$0.isArchived })

        // Filter
        if !searchText.isEmpty {
            all = all.filter { note in
                note.title.localizedCaseInsensitiveContains(searchText)
                || note.bodyPlainText.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Sort
        let sorted = sortNotes(all)

        // Split into sections
        pinnedNotes = sorted.filter { $0.isPinned }
        otherNotes  = sorted.filter { !$0.isPinned }

        // Build flat row list
        rows = []
        if !pinnedNotes.isEmpty {
            rows.append(.sectionHeader("Pinned"))
            rows.append(contentsOf: pinnedNotes.map { .note($0) })
        }
        if !otherNotes.isEmpty {
            let headerTitle = pinnedNotes.isEmpty ? "Notes" : "Others"
            rows.append(.sectionHeader(headerTitle))
            rows.append(contentsOf: otherNotes.map { .note($0) })
        }

        let isEmpty = pinnedNotes.isEmpty && otherNotes.isEmpty
        emptyLabel.isHidden = !isEmpty
        emptyLabel.stringValue = searchText.isEmpty ? "No notes yet" : "No matching notes"
        scrollView.isHidden = isEmpty

        tableView.reloadData()
    }

    private func sortNotes(_ notes: [NoteRecord]) -> [NoteRecord] {
        switch sortMode {
        case .updatedDate:
            return notes.sorted { $0.updatedAt > $1.updatedAt }
        case .createdDate:
            return notes.sorted { $0.createdAt > $1.createdAt }
        case .titleAZ:
            return notes.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .titleZA:
            return notes.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .manual:
            return notes.sorted { $0.manualSortOrder < $1.manualSortOrder }
        }
    }

    func selectNote(id: UUID) {
        guard let idx = rows.firstIndex(where: {
            if case .note(let n) = $0 { return n.id == id }
            return false
        }) else { return }
        tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        tableView.scrollRowToVisible(idx)
    }

    private func noteAt(row: Int) -> NoteRecord? {
        guard row >= 0, row < rows.count else { return nil }
        if case .note(let note) = rows[row] { return note }
        return nil
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count else { return nil }

        switch rows[row] {
        case .sectionHeader(let title):
            let headerID = NSUserInterfaceItemIdentifier("SectionHeader")
            let header = (tableView.makeView(withIdentifier: headerID, owner: nil) as? NSTextField)
                ?? {
                    let h = NSTextField(labelWithString: "")
                    h.identifier = headerID
                    h.font = .systemFont(ofSize: 11, weight: .semibold)
                    h.textColor = .secondaryLabelColor
                    return h
                }()
            header.stringValue = title.uppercased()
            return header

        case .note(let note):
            let cellID = NSUserInterfaceItemIdentifier("NoteCell")
            let cell = (tableView.makeView(withIdentifier: cellID, owner: nil) as? AllNotesCellView)
                ?? AllNotesCellView(identifier: cellID)
            cell.configure(with: note, isOpen: isWindowOpen?(note.id) ?? false)
            return cell
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row < rows.count else { return 68 }
        if case .sectionHeader = rows[row] { return 28 }
        return 68
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        guard row < rows.count else { return false }
        if case .sectionHeader = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard row < rows.count else { return false }
        if case .sectionHeader = rows[row] { return false }
        return true
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let note = noteAt(row: tableView.selectedRow) else { return }
        onSelectNote?(note.id)
    }

    // MARK: - Swipe Actions

    func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
        guard let note = noteAt(row: row) else { return [] }

        switch edge {
        case .trailing:
            // Swipe left → Delete
            let delete = NSTableViewRowAction(style: .destructive, title: "Delete") { [weak self] _, _ in
                self?.onDeleteNote?(note.id)
            }
            delete.backgroundColor = .systemRed
            return [delete]

        case .leading:
            // Swipe right → Pin/Unpin
            let isPinned = note.isPinned
            let title = isPinned ? "Unpin" : "Pin"
            let pin = NSTableViewRowAction(style: .regular, title: title) { [weak self] _, _ in
                self?.noteStore?.updatePinned(noteID: note.id, isPinned: !isPinned)
            }
            pin.backgroundColor = .systemOrange
            return [pin]

        @unknown default:
            return []
        }
    }

    // MARK: - Drag & Drop

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        // Allow dragging for note rows in any sort mode
        guard let note = noteAt(row: row) else { return nil }
        let item = NSPasteboardItem()
        item.setString(note.id.uuidString, forType: noteRowDragType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if dropOperation == .above { return .move }
        return []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let store = noteStore,
              let idString = info.draggingPasteboard.string(forType: noteRowDragType),
              let draggedID = UUID(uuidString: idString),
              let draggedNote = store.notes[draggedID] else { return false }

        // Determine which section the dragged note belongs to
        let isPinned = draggedNote.isPinned
        var targetList = isPinned ? pinnedNotes : otherNotes

        // Find the insert position within that section
        var targetIndex = targetList.count

        if row < rows.count, let targetNote = noteAt(row: row) {
            // Only reorder within the same section (pinned↔pinned, other↔other)
            if targetNote.isPinned == isPinned {
                if let idx = targetList.firstIndex(where: { $0.id == targetNote.id }) {
                    targetIndex = idx
                }
            }
        } else if row > 0, let prevNote = noteAt(row: row - 1) {
            // Dropping at the end of a section
            if prevNote.isPinned == isPinned {
                targetIndex = targetList.count
            }
        }

        // Remove dragged note and reinsert at target position
        targetList.removeAll { $0.id == draggedID }
        targetList.insert(draggedNote, at: min(targetIndex, targetList.count))

        // Reassign ordinal sort orders for the entire section
        for (i, note) in targetList.enumerated() {
            store.updateManualSortOrder(noteID: note.id, order: i)
        }

        // Switch to manual sort mode so the new order is visible
        if sortMode != .manual {
            sortMode = .manual
        } else {
            reloadData()
        }
        return true
    }

    // MARK: - NSSearchFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        searchText = searchField.stringValue
        reloadData()
    }

    // MARK: - Actions

    @objc func createClicked() {
        onCreateNote?()
    }

    @objc private func rowDoubleClicked() {
        guard let note = noteAt(row: tableView.clickedRow) else { return }
        onOpenNote?(note.id)
    }

    @objc private func contextOpen(_ sender: Any?) {
        guard let note = noteAt(row: tableView.clickedRow) else { return }
        onOpenNote?(note.id)
    }

    @objc private func contextDelete(_ sender: Any?) {
        guard let note = noteAt(row: tableView.clickedRow) else { return }
        onDeleteNote?(note.id)
    }

    @objc private func contextPin(_ sender: Any?) {
        guard let note = noteAt(row: tableView.clickedRow) else { return }
        noteStore?.updatePinned(noteID: note.id, isPinned: !note.isPinned)
    }

    // MARK: - Context Menu

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open in Window", action: #selector(contextOpen(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let pinItem = menu.addItem(withTitle: "Pin / Unpin", action: #selector(contextPin(_:)), keyEquivalent: "")
        pinItem.target = self
        menu.addItem(.separator())
        let deleteItem = menu.addItem(withTitle: "Delete", action: #selector(contextDelete(_:)), keyEquivalent: "")
        deleteItem.target = self
        return menu
    }
}

// MARK: - AllNotesCellView

final class AllNotesCellView: NSTableCellView {

    private let swatchView = NSView(frame: .zero)
    private let titleLabel = NSTextField(labelWithString: "")
    private let excerptLabel = NSTextField(labelWithString: "")
    private let timestampLabel = NSTextField(labelWithString: "")
    private let pinImage = NSImageView()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        swatchView.wantsLayer = true
        swatchView.layer?.cornerRadius = 6
        swatchView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(swatchView)

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        let pinConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .regular)
        pinImage.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")?
            .withSymbolConfiguration(pinConfig)
        pinImage.contentTintColor = .secondaryLabelColor
        pinImage.translatesAutoresizingMaskIntoConstraints = false
        pinImage.isHidden = true
        addSubview(pinImage)

        excerptLabel.font = .systemFont(ofSize: 11)
        excerptLabel.textColor = .secondaryLabelColor
        excerptLabel.lineBreakMode = .byTruncatingTail
        excerptLabel.maximumNumberOfLines = 1
        excerptLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(excerptLabel)

        timestampLabel.font = .systemFont(ofSize: 10)
        timestampLabel.textColor = .tertiaryLabelColor
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timestampLabel)

        NSLayoutConstraint.activate([
            swatchView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            swatchView.centerYAnchor.constraint(equalTo: centerYAnchor),
            swatchView.widthAnchor.constraint(equalToConstant: 12),
            swatchView.heightAnchor.constraint(equalToConstant: 12),

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: swatchView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),

            pinImage.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            pinImage.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 4),
            pinImage.widthAnchor.constraint(equalToConstant: 12),

            excerptLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            excerptLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            excerptLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            timestampLabel.topAnchor.constraint(equalTo: excerptLabel.bottomAnchor, constant: 2),
            timestampLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            timestampLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            timestampLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6),
        ])
    }

    func configure(with note: NoteRecord, isOpen: Bool) {
        let theme = ThemeRegistry.theme(for: note.themeID)
        swatchView.layer?.backgroundColor = theme.headerBackgroundColor.cgColor

        if note.title.isEmpty {
            titleLabel.stringValue = "Untitled"
            titleLabel.textColor = .secondaryLabelColor
        } else {
            titleLabel.stringValue = note.title
            titleLabel.textColor = .labelColor
        }

        pinImage.isHidden = !note.isPinned

        excerptLabel.stringValue = note.bodyExcerpt
        excerptLabel.isHidden = note.bodyExcerpt.isEmpty

        timestampLabel.stringValue = Self.relativeDate(note.updatedAt)
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static func relativeDate(_ date: Date) -> String {
        relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
}
