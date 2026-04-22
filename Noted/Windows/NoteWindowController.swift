import AppKit

// MARK: - NoteWindowController

/// Manages one note window. Coordinates between the content view, the editor,
/// and the note store.
final class NoteWindowController: NSWindowController, NSWindowDelegate {

    let noteID: UUID
    private let contentView: NoteContentView
    private let editorCoordinator: NoteEditorCoordinator
    private weak var noteStore: NoteStore?

    // MARK: - Init

    init(noteID: UUID, noteStore: NoteStore, frame: NSRect, theme: NoteTheme) {
        self.noteID = noteID
        self.noteStore = noteStore

        // Create content view
        contentView = NoteContentView(noteID: noteID, theme: theme)
        editorCoordinator = NoteEditorCoordinator(noteID: noteID, noteStore: noteStore)

        // Create window
        let window = NoteWindow(contentRect: frame)
        window.contentView = contentView
        contentView.frame = window.contentView!.bounds
        contentView.autoresizingMask = [.width, .height]

        super.init(window: window)

        window.delegate = self
        contentView.delegate = self
        contentView.textView.delegate = editorCoordinator

        Log.window.debug("Created window controller for note \(noteID)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Public

    func loadContent(from note: NoteRecord) {
        contentView.titleField.stringValue = note.title
        contentView.loadBody(from: note.attributedBodyData)
        contentView.updatePinState(note.isPinned)
        applyPinLevel(note.isPinned)

        // Place caret at end
        let length = contentView.textView.textStorage?.length ?? 0
        contentView.textView.setSelectedRange(NSRange(location: length, length: 0))
    }

    func applyTheme(_ theme: NoteTheme) {
        contentView.applyTheme(theme)
    }

    func focusEditor() {
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(contentView.textView)
    }

    /// Called by ResizeHandleView on mouseUp.
    func windowDidEndResize() {
        persistFrame()
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        // Ensure editor is ready
    }

    func windowDidMove(_ notification: Notification) {
        persistFrame()
    }

    func windowWillClose(_ notification: Notification) {
        // Mark note as closed, do NOT delete.
        noteStore?.markClosed(noteID: noteID, isClosed: true)
        // Notify window manager
        NotificationCenter.default.post(name: .noteWindowDidClose, object: noteID)
        Log.window.debug("Window closed for note \(self.noteID)")
    }

    func windowDidResize(_ notification: Notification) {
        // Update text view container size
        if let scrollWidth = contentView.editorScrollView.contentView.documentVisibleRect.width as CGFloat? {
            contentView.textView.textContainer?.containerSize = NSSize(
                width: max(1, scrollWidth - 24), // account for textContainerInset
                height: CGFloat.greatestFiniteMagnitude
            )
        }
    }

    // MARK: - Private

    private func persistFrame() {
        guard let frame = window?.frame else { return }
        noteStore?.updateFrame(noteID: noteID, frame: PersistedRect(from: frame))
    }

    private func applyPinLevel(_ pinned: Bool) {
        window?.level = pinned ? .floating : .normal
    }
}

// MARK: - NoteContentViewDelegate

extension NoteWindowController: NoteContentViewDelegate {

    func noteContentView(_ view: NoteContentView, didCommitTitle title: String) {
        noteStore?.updateTitle(noteID: noteID, title: title)
    }

    func noteContentViewDidClickClose(_ view: NoteContentView) {
        window?.close()
    }

    func noteContentViewDidClickPin(_ view: NoteContentView) {
        guard let note = noteStore?.notes[noteID] else { return }
        let newPinned = !note.isPinned
        noteStore?.updatePinned(noteID: noteID, isPinned: newPinned)
        contentView.updatePinState(newPinned)
        applyPinLevel(newPinned)
    }

    func noteContentView(_ view: NoteContentView, didSelectTheme themeID: String) {
        noteStore?.updateTheme(noteID: noteID, themeID: themeID)
        let theme = ThemeRegistry.theme(for: themeID)
        applyTheme(theme)
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let noteWindowDidClose = Notification.Name("noteWindowDidClose")
}
