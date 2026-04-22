import AppKit
import Combine

// MARK: - AllNotesViewController

/// Pure AppKit implementation of the All Notes list.
///
/// Liquid Glass design:
/// - `NSVisualEffectView` with `.sidebar` material as the window background
///   for the translucent glass effect.
/// - `NSToolbar` for the search field and actions — toolbars automatically
///   adopt Liquid Glass on macOS 26.
/// - Transparent table view so the material shows through between rows.
/// - Vibrant label colors for text legibility on translucent backgrounds.
final class AllNotesViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

    // MARK: - Callbacks

    var onSelectNote: ((UUID) -> Void)?   // single click → preview in detail
    var onOpenNote: ((UUID) -> Void)?     // double click → standalone window
    var onDeleteNote: ((UUID) -> Void)?
    var onCreateNote: (() -> Void)?
    var isWindowOpen: ((UUID) -> Bool)?

    // MARK: - Data

    private weak var noteStore: NoteStore?
    private var cancellable: AnyCancellable?
    private var filteredNotes: [NoteRecord] = []
    private var searchText: String = ""

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
        // Plain NSView — the NSSplitViewItem(sidebarWithViewController:)
        // provides the Liquid Glass sidebar material automatically.
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 500))

        // Search field (hosted in toolbar, configured here for delegate)
        searchField.placeholderString = "Search notes…"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true

        // ── Table view ──
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

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        // Empty state label
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
        let all = store.notes.values
            .filter { !$0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }

        if searchText.isEmpty {
            filteredNotes = Array(all)
        } else {
            filteredNotes = all.filter { note in
                note.title.localizedCaseInsensitiveContains(searchText)
                || note.bodyPlainText.localizedCaseInsensitiveContains(searchText)
            }
        }

        let isEmpty = filteredNotes.isEmpty
        emptyLabel.isHidden = !isEmpty
        emptyLabel.stringValue = searchText.isEmpty ? "No notes yet" : "No matching notes"
        scrollView.isHidden = isEmpty

        tableView.reloadData()
    }

    /// Programmatically select a note in the list (e.g. after create).
    func selectNote(id: UUID) {
        guard let idx = filteredNotes.firstIndex(where: { $0.id == id }) else { return }
        tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        tableView.scrollRowToVisible(idx)
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredNotes.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredNotes.count else { return nil }
        let note = filteredNotes[row]
        let cellID = NSUserInterfaceItemIdentifier("NoteCell")
        let cell = (tableView.makeView(withIdentifier: cellID, owner: nil) as? AllNotesCellView)
            ?? AllNotesCellView(identifier: cellID)
        cell.configure(with: note, isOpen: isWindowOpen?(note.id) ?? false)
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        68
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredNotes.count else { return }
        onSelectNote?(filteredNotes[row].id)
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
        let row = tableView.clickedRow
        guard row >= 0, row < filteredNotes.count else { return }
        onOpenNote?(filteredNotes[row].id)
    }

    @objc private func contextOpen(_ sender: Any?) {
        let row = tableView.clickedRow
        guard row >= 0, row < filteredNotes.count else { return }
        onOpenNote?(filteredNotes[row].id)
    }

    @objc private func contextDelete(_ sender: Any?) {
        let row = tableView.clickedRow
        guard row >= 0, row < filteredNotes.count else { return }
        onDeleteNote?(filteredNotes[row].id)
    }

    // MARK: - Context Menu

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open", action: #selector(contextOpen(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let deleteItem = menu.addItem(withTitle: "Delete", action: #selector(contextDelete(_:)), keyEquivalent: "")
        deleteItem.target = self
        return menu
    }
}

// MARK: - AllNotesCellView

/// A table cell with theme swatch, title, excerpt, timestamp, pin & open-state indicators.
/// Uses vibrant label colors for Liquid Glass legibility.
final class AllNotesCellView: NSTableCellView {

    private let swatchView = NSView(frame: .zero)
    private let titleLabel = NSTextField(labelWithString: "")
    private let excerptLabel = NSTextField(labelWithString: "")
    private let timestampLabel = NSTextField(labelWithString: "")
    private let pinImage = NSImageView()
    private let closedImage = NSImageView()

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

        let closedConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        closedImage.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Window closed")?
            .withSymbolConfiguration(closedConfig)
        closedImage.contentTintColor = .quaternaryLabelColor
        closedImage.toolTip = "Window closed"
        closedImage.translatesAutoresizingMaskIntoConstraints = false
        closedImage.isHidden = true
        addSubview(closedImage)

        NSLayoutConstraint.activate([
            swatchView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            swatchView.centerYAnchor.constraint(equalTo: centerYAnchor),
            swatchView.widthAnchor.constraint(equalToConstant: 12),
            swatchView.heightAnchor.constraint(equalToConstant: 12),

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: swatchView.trailingAnchor, constant: 10),

            pinImage.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            pinImage.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 4),
            pinImage.widthAnchor.constraint(equalToConstant: 12),

            closedImage.centerYAnchor.constraint(equalTo: centerYAnchor),
            closedImage.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closedImage.leadingAnchor, constant: -8),

            excerptLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            excerptLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            excerptLabel.trailingAnchor.constraint(equalTo: closedImage.leadingAnchor, constant: -8),

            timestampLabel.topAnchor.constraint(equalTo: excerptLabel.bottomAnchor, constant: 2),
            timestampLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            timestampLabel.trailingAnchor.constraint(lessThanOrEqualTo: closedImage.leadingAnchor, constant: -8),
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
        closedImage.isHidden = isOpen

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
