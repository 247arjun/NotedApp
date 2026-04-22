import AppKit

// MARK: - NoteEditorCoordinator

/// Bridges NSTextView delegate events back to the NoteStore.
@MainActor
final class NoteEditorCoordinator: NSObject, NSTextViewDelegate {

    let noteID: UUID
    weak var noteStore: NoteStore?

    init(noteID: UUID, noteStore: NoteStore) {
        self.noteID = noteID
        self.noteStore = noteStore
        super.init()
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView,
              let storage = textView.textStorage else { return }

        let range = NSRange(location: 0, length: storage.length)
        do {
            let data = try storage.data(
                from: range,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            noteStore?.updateBody(noteID: noteID, attributedData: data)
        } catch {
            Log.editor.error("Failed to serialize body for note \(self.noteID): \(error.localizedDescription)")
        }
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Let standard commands pass through
        return false
    }
}
