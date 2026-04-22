import AppKit
import Combine

// MARK: - NoteDetailViewController

/// Detail pane for the All Notes split view.
/// Embeds a NoteContentView (title + editor) with header controls hidden —
/// the controls live in the window toolbar as a compact button group instead.
@MainActor
final class NoteDetailViewController: NSViewController, NoteContentViewDelegate {

    // MARK: - Callbacks

    var onDeleteNote: ((UUID) -> Void)?
    var onThemeChanged: ((UUID, String) -> Void)?
    var onWindowColorChanged: ((NSColor?) -> Void)?

    // MARK: - State

    private(set) var currentNoteID: UUID?
    private weak var noteStore: NoteStore?
    private var editorCoordinator: NoteEditorCoordinator?

    private var noteContentView: NoteContentView?
    private let placeholderLabel = NSTextField(labelWithString: "Select a note")
    private var storeCancellable: AnyCancellable?

    // MARK: - Toolbar Item IDs

    static let controlGroupID = NSToolbarItem.Identifier("NoteControlGroup")
    static let pinItemID      = NSToolbarItem.Identifier("PinItem")
    static let themeItemID    = NSToolbarItem.Identifier("ThemeItem")
    static let deleteItemID   = NSToolbarItem.Identifier("DeleteItem")
    static let closeItemID    = NSToolbarItem.Identifier("CloseItem")

    // MARK: - Init

    init(noteStore: NoteStore) {
        self.noteStore = noteStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        root.wantsLayer = true

        placeholderLabel.font = .systemFont(ofSize: 16)
        placeholderLabel.textColor = .tertiaryLabelColor
        placeholderLabel.alignment = .center
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            placeholderLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])

        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Observe store changes to refresh detail when edited externally
        // (e.g. from a standalone note window).
        storeCancellable = noteStore?.objectWillChange
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshFromStoreIfNeeded()
            }
    }

    // MARK: - Public

    func showNote(id: UUID) {
        guard let store = noteStore, let note = store.notes[id] else { return }

        if currentNoteID == id, let contentView = noteContentView {
            contentView.titleField.stringValue = note.title
            contentView.updatePinState(note.isPinned)
            refreshToolbarItems()
            return
        }

        noteContentView?.removeFromSuperview()
        noteContentView = nil
        editorCoordinator = nil

        currentNoteID = id
        placeholderLabel.isHidden = true

        let theme = ThemeRegistry.theme(for: note.themeID)
        let contentView = NoteContentView(noteID: id, theme: theme)
        contentView.delegate = self
        contentView.hidesHeaderControls = true   // controls live in toolbar
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let coordinator = NoteEditorCoordinator(noteID: id, noteStore: store)
        contentView.textView.delegate = coordinator
        self.editorCoordinator = coordinator

        contentView.titleField.stringValue = note.title
        contentView.loadBody(from: note.attributedBodyData)
        contentView.updatePinState(note.isPinned)

        view.addSubview(contentView)

        contentView.layer?.cornerRadius = 0
        contentView.layer?.masksToBounds = false

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        self.noteContentView = contentView
        updateWindowColor(for: theme)
        refreshToolbarItems()

        DispatchQueue.main.async {
            self.view.window?.makeFirstResponder(contentView.textView)
        }
    }

    func clearDetail() {
        noteContentView?.removeFromSuperview()
        noteContentView = nil
        editorCoordinator = nil
        currentNoteID = nil
        placeholderLabel.isHidden = false
        onWindowColorChanged?(nil)
        refreshToolbarItems()
    }

    /// Refresh the detail pane from the store if an external change occurred
    /// (e.g. the user edited the same note in a standalone window).
    private func refreshFromStoreIfNeeded() {
        guard let id = currentNoteID,
              let store = noteStore,
              let note = store.notes[id],
              let contentView = noteContentView else { return }

        // Skip if our own editor coordinator made this change
        if editorCoordinator?.isLocalEdit == true { return }

        // Refresh title
        if contentView.titleField.stringValue != note.title {
            contentView.titleField.stringValue = note.title
        }

        // Refresh body — only if the text actually differs to avoid cursor jumps
        let currentData: Data
        do {
            let storage = contentView.textView.textStorage!
            currentData = try storage.data(
                from: NSRange(location: 0, length: storage.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        } catch {
            currentData = Data()
        }

        if currentData != note.attributedBodyData {
            contentView.loadBody(from: note.attributedBodyData)
        }

        // Refresh pin state
        contentView.updatePinState(note.isPinned)

        // Refresh theme if changed
        if contentView.theme.id != note.themeID {
            let theme = ThemeRegistry.theme(for: note.themeID)
            contentView.applyTheme(theme)
            updateWindowColor(for: theme)
        }
    }

    // MARK: - Toolbar

    /// Rebuild the toolbar to show/hide note controls based on selection.
    func refreshToolbarItems() {
        guard let toolbar = view.window?.toolbar else { return }
        // Remove existing control group if present
        if let idx = toolbar.items.firstIndex(where: { $0.itemIdentifier == Self.controlGroupID }) {
            toolbar.removeItem(at: idx)
        }
        // Re-add control group if a note is selected (forces refresh of pin state etc.)
        if currentNoteID != nil {
            toolbar.insertItem(withItemIdentifier: Self.controlGroupID, at: toolbar.items.count)
        }
    }

    /// Creates the NSToolbarItemGroup for pin/theme/delete/close.
    /// Called by the window controller's toolbar delegate.
    func makeControlGroupItem() -> NSToolbarItem {
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)

        let pinItem = NSToolbarItem(itemIdentifier: Self.pinItemID)
        let isPinned = noteStore?.notes[currentNoteID ?? UUID()]?.isPinned ?? false
        let pinSymbol = isPinned ? "pin.fill" : "pin"
        pinItem.image = NSImage(systemSymbolName: pinSymbol, accessibilityDescription: isPinned ? "Unpin note" : "Pin note")?
            .withSymbolConfiguration(iconConfig)
        pinItem.label = "Pin"
        pinItem.target = self
        pinItem.action = #selector(toolbarPinClicked)

        let themeItem = NSToolbarItem(itemIdentifier: Self.themeItemID)
        themeItem.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: "Change note color")?
            .withSymbolConfiguration(iconConfig)
        themeItem.label = "Color"
        themeItem.target = self
        themeItem.action = #selector(toolbarThemeClicked(_:))

        let deleteItem = NSToolbarItem(itemIdentifier: Self.deleteItemID)
        deleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete note")?
            .withSymbolConfiguration(iconConfig)
        deleteItem.label = "Delete"
        deleteItem.target = self
        deleteItem.action = #selector(toolbarDeleteClicked)

        let closeItem = NSToolbarItem(itemIdentifier: Self.closeItemID)
        closeItem.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close preview")?
            .withSymbolConfiguration(iconConfig)
        closeItem.label = "Close"
        closeItem.target = self
        closeItem.action = #selector(toolbarCloseClicked)

        let group = NSToolbarItemGroup(itemIdentifier: Self.controlGroupID)
        group.subitems = [pinItem, themeItem, deleteItem, closeItem]
        group.controlRepresentation = .automatic
        group.selectionMode = .momentary
        group.label = "Note Actions"
        return group
    }

    // MARK: - Toolbar Actions

    @objc private func toolbarPinClicked() {
        guard let cv = noteContentView else { return }
        noteContentViewDidClickPin(cv)
        refreshToolbarItems()
    }

    @objc private func toolbarThemeClicked(_ sender: Any?) {
        // Show theme popover from toolbar — find the toolbar item's view
        guard let cv = noteContentView else { return }
        // Find the toolbar item view for theme
        if let toolbarView = view.window?.toolbar?.items
            .first(where: { $0.itemIdentifier == Self.controlGroupID })?
            .view {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentSize = NSSize(width: 200, height: 50)
            let pickerVC = ThemePickerViewController(currentThemeID: cv.theme.id) { [weak self] selectedID in
                guard let self else { return }
                popover.performClose(nil)
                self.noteContentView(cv, didSelectTheme: selectedID)
            }
            popover.contentViewController = pickerVC
            popover.show(relativeTo: toolbarView.bounds, of: toolbarView, preferredEdge: .minY)
        }
    }

    @objc private func toolbarDeleteClicked() {
        guard let cv = noteContentView else { return }
        noteContentViewDidClickDelete(cv)
    }

    @objc private func toolbarCloseClicked() {
        clearDetail()
    }

    // MARK: - NoteContentViewDelegate

    func noteContentView(_ view: NoteContentView, didCommitTitle title: String) {
        guard let id = currentNoteID else { return }
        noteStore?.updateTitle(noteID: id, title: title)
    }

    func noteContentViewDidClickClose(_ view: NoteContentView) {
        clearDetail()
    }

    func noteContentViewDidClickDelete(_ view: NoteContentView) {
        guard let id = currentNoteID else { return }
        guard let window = self.view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Delete Note?"
        alert.informativeText = "This note will be permanently deleted. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.clearDetail()
            self?.onDeleteNote?(id)
        }
    }

    func noteContentViewDidClickPin(_ view: NoteContentView) {
        guard let id = currentNoteID, let store = noteStore else { return }
        guard let note = store.notes[id] else { return }
        let newPinned = !note.isPinned
        store.updatePinned(noteID: id, isPinned: newPinned)
        view.updatePinState(newPinned)
    }

    func noteContentView(_ view: NoteContentView, didSelectTheme themeID: String) {
        guard let id = currentNoteID else { return }
        noteStore?.updateTheme(noteID: id, themeID: themeID)
        let theme = ThemeRegistry.theme(for: themeID)
        view.applyTheme(theme)
        updateWindowColor(for: theme)
        onThemeChanged?(id, themeID)
    }

    // MARK: - Private

    private func updateWindowColor(for theme: NoteTheme) {
        let tinted = theme.bodyBackgroundColor.withAlphaComponent(0.55)
        onWindowColorChanged?(tinted)
    }
}
