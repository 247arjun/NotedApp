import AppKit
import Combine

// MARK: - AllNotesViewController

/// Pure AppKit implementation of the All Notes list.
/// Uses NSTableView with a search field, create button, and context menus.
final class AllNotesViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

    // MARK: - Callbacks

    var onOpenNote: ((UUID) -> Void)?
    var onDeleteNote: ((UUID) -> Void)?
    var onCreateNote: (() -> Void)?
    var isWindowOpen: ((UUID) -> Bool)?

    // MARK: - Data

    private weak var noteStore: NoteStore?
    private var cancellable: AnyCancellable?
    private var filteredNotes: [NoteRecord] = []
    private var searchText: String = ""

    // MARK: - Subviews

    private let searchField = NSSearchField()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let createButton = NSButton()
    private let emptyLabel = NSTextField(labelWithString: "No notes yet")

    // MARK: - Column IDs

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
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 500))
        root.wantsLayer = true

        // Header: title + create button
        let titleLabel = NSTextField(labelWithString: "All Notes")
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(titleLabel)

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        createButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Note")?
            .withSymbolConfiguration(config)
        createButton.isBordered = false
        createButton.bezelStyle = .inline
        createButton.target = self
        createButton.action = #selector(createClicked)
        createButton.setAccessibilityLabel("New Note")
        createButton.toolTip = "New Note"
        createButton.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(createButton)

        // Search field
        searchField.placeholderString = "Search notes…"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(searchField)

        // Table view
        let column = NSTableColumn(identifier: Self.noteColumnID)
        column.title = ""
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 64
        tableView.style = .inset
        tableView.allowsMultipleSelection = false
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.target = self
        tableView.menu = buildContextMenu()

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        // Empty state
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),

            createButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            createButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),

            searchField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
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

        // Observe store changes
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
                || note.bodyExcerpt.localizedCaseInsensitiveContains(searchText)
            }
        }

        let isEmpty = filteredNotes.isEmpty
        emptyLabel.isHidden = !isEmpty
        emptyLabel.stringValue = searchText.isEmpty ? "No notes yet" : "No matching notes"
        scrollView.isHidden = isEmpty

        tableView.reloadData()
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
        64
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredNotes.count else { return }
        let note = filteredNotes[row]
        onOpenNote?(note.id)
    }

    // MARK: - NSSearchFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        searchText = searchField.stringValue
        reloadData()
    }

    // MARK: - Actions

    @objc private func createClicked() {
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

/// A table cell that shows theme swatch, title, excerpt, timestamp, pin & open state.
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
        excerptLabel.maximumNumberOfLines = 2
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
