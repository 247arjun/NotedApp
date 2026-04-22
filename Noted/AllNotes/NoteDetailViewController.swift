import AppKit

// MARK: - NoteDetailViewController

/// Detail pane for the All Notes split view.
/// Embeds a full NoteContentView (header + editor + controls) so the user
/// can preview and edit a note inline, including theme and delete actions.
///
/// Liquid Glass: Uses NSVisualEffectView with `.contentBackground` material.
@MainActor
final class NoteDetailViewController: NSViewController, NoteContentViewDelegate {

    // MARK: - Callbacks

    var onDeleteNote: ((UUID) -> Void)?
    var onThemeChanged: ((UUID, String) -> Void)?
    /// Called when the detail pane wants to tint the window background.
    /// Pass nil to reset to default (no note selected).
    var onWindowColorChanged: ((NSColor?) -> Void)?

    // MARK: - State

    private(set) var currentNoteID: UUID?
    private weak var noteStore: NoteStore?
    private var editorCoordinator: NoteEditorCoordinator?

    private var noteContentView: NoteContentView?
    private let placeholderLabel = NSTextField(labelWithString: "Select a note")

    // MARK: - Init

    init(noteStore: NoteStore) {
        self.noteStore = noteStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func loadView() {
        // Use a plain NSView so the window's tinted backgroundColor shows through.
        // The NoteContentView provides its own themed background.
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        root.wantsLayer = true

        // Placeholder shown when no note is selected
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

    // MARK: - Public

    /// Show the given note in the detail pane.
    func showNote(id: UUID) {
        guard let store = noteStore, let note = store.notes[id] else { return }

        // If same note, just refresh content
        if currentNoteID == id, let contentView = noteContentView {
            contentView.titleField.stringValue = note.title
            contentView.updatePinState(note.isPinned)
            return
        }

        // Tear down previous
        noteContentView?.removeFromSuperview()
        noteContentView = nil
        editorCoordinator = nil

        currentNoteID = id
        placeholderLabel.isHidden = true

        // Build new NoteContentView
        let theme = ThemeRegistry.theme(for: note.themeID)
        let contentView = NoteContentView(noteID: id, theme: theme)
        contentView.delegate = self
        contentView.translatesAutoresizingMaskIntoConstraints = false

        // Set up editor coordinator
        let coordinator = NoteEditorCoordinator(noteID: id, noteStore: store)
        contentView.textView.delegate = coordinator
        self.editorCoordinator = coordinator

        // Load content
        contentView.titleField.stringValue = note.title
        contentView.loadBody(from: note.attributedBodyData)
        contentView.updatePinState(note.isPinned)

        view.addSubview(contentView)

        // Disable rounded corners when embedded in the split view detail pane —
        // the window chrome provides its own rounding.
        contentView.layer?.cornerRadius = 0
        contentView.layer?.masksToBounds = false

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        self.noteContentView = contentView

        // Tint the window background with the note's theme color
        updateWindowColor(for: theme)

        // Focus editor
        DispatchQueue.main.async {
            self.view.window?.makeFirstResponder(contentView.textView)
        }
    }

    /// Clear the detail pane (e.g. when note is deleted).
    func clearDetail() {
        noteContentView?.removeFromSuperview()
        noteContentView = nil
        editorCoordinator = nil
        currentNoteID = nil
        placeholderLabel.isHidden = false
        onWindowColorChanged?(nil)
    }

    // MARK: - NoteContentViewDelegate

    func noteContentView(_ view: NoteContentView, didCommitTitle title: String) {
        guard let id = currentNoteID else { return }
        noteStore?.updateTitle(noteID: id, title: title)
    }

    func noteContentViewDidClickClose(_ view: NoteContentView) {
        // In the detail pane, "close" clears the preview
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
        // Translucent tint of the note's body color — blends through the sidebar's
        // behindWindow glass, giving the whole window a subtle colored hue.
        let tinted = theme.bodyBackgroundColor.withAlphaComponent(0.55)
        onWindowColorChanged?(tinted)
    }
}
