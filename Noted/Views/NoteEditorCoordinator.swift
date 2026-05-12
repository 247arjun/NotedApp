import AppKit
import NotedKit

// MARK: - NoteEditorCoordinator

/// Bridges NSTextView delegate events back to the NoteStore.
@MainActor
final class NoteEditorCoordinator: NSObject, NSTextViewDelegate {

    let noteID: UUID
    weak var noteStore: NoteStore?

    /// True while this coordinator is actively pushing changes to the store.
    /// Used to avoid re-reading our own edits from the store.
    private(set) var isLocalEdit = false

    init(noteID: UUID, noteStore: NoteStore) {
        self.noteID = noteID
        self.noteStore = noteStore
        super.init()
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView,
              let storage = textView.textStorage else { return }

        // Markdown shortcut detection — collapse **bold**, *italic*, `code`
        // etc. in-place when the closing marker is typed.
        if let edited = lastEditedRange(in: textView) {
            let baseFont = AppSettings.shared.defaultFont
            let result = MarkdownShortcuts.processEdit(
                in: storage,
                editedRange: edited,
                baseFont: baseFont
            )
            if result.replaced, result.newCaret >= 0 {
                textView.setSelectedRange(NSRange(location: result.newCaret, length: 0))
            }
        }

        let range = NSRange(location: 0, length: storage.length)
        do {
            let data = try storage.data(
                from: range,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            isLocalEdit = true
            noteStore?.updateBody(noteID: noteID, attributedData: data)
            isLocalEdit = false
        } catch {
            Log.editor.error("Failed to serialize body for note \(self.noteID): \(error.localizedDescription)")
        }
    }

    /// Best-effort guess at the range that was just edited. NSTextView
    /// doesn't surface the inserted range directly; we treat the empty
    /// selection at the caret as the tail of the most recent insert.
    private func lastEditedRange(in textView: NSTextView) -> NSRange? {
        let sel = textView.selectedRange()
        guard sel.length == 0, sel.location > 0 else { return nil }
        return NSRange(location: sel.location - 1, length: 1)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Let standard commands pass through
        return false
    }
}
