import AppKit
import Combine

// MARK: - AppCoordinator

/// Central coordinator that owns the note store, window manager, and persistence.
/// Accessed as a shared singleton from both SwiftUI and AppKit.
@MainActor
final class AppCoordinator: ObservableObject {

    static let shared = AppCoordinator()

    let noteStore: NoteStore
    let windowManager: WindowManager
    let persistenceService: PersistenceService

    private var allNotesWindowController: AllNotesWindowController?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let persistence = FilePersistenceService()
        let store = NoteStore(persistenceService: persistence)

        self.persistenceService = persistence
        self.noteStore = store
        self.windowManager = WindowManager(noteStore: store)
    }

    // MARK: - App Lifecycle

    /// Called on applicationDidFinishLaunching.
    func start() {
        noteStore.loadAll()

        if noteStore.notes.isEmpty {
            // First launch: create a welcome note
            createNewNote()
        } else {
            windowManager.restoreAllWindows()
        }
    }

    /// Flush all pending saves before app terminates.
    func flushPendingSaves() {
        noteStore.flushPendingSaves()
    }

    // MARK: - Note Actions

    @objc func createNewNote() {
        let note = noteStore.createNote()
        windowManager.openNewNoteWindow(noteID: note.id)
        Log.note.info("User created new note \(note.id)")
    }

    func closeNote(noteID: UUID) {
        windowManager.closeWindow(for: noteID)
    }

    @objc func duplicateCurrentNote() {
        guard let noteID = currentNoteID() else { return }
        if let dup = noteStore.duplicateNote(noteID: noteID) {
            windowManager.openNewNoteWindow(noteID: dup.id)
        }
    }

    func openNote(noteID: UUID) {
        windowManager.openWindow(for: noteID)
    }

    func deleteNote(noteID: UUID) {
        windowManager.closeWindow(for: noteID)
        noteStore.deleteNote(noteID: noteID)
    }

    @objc func deleteCurrentNote() {
        guard let noteID = currentNoteID(),
              let window = NSApp.keyWindow else { return }
        let alert = NSAlert()
        alert.messageText = "Delete Note?"
        alert.informativeText = "This note will be permanently deleted. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.deleteNote(noteID: noteID)
        }
    }

    // MARK: - All Notes Window

    @objc func showAllNotes() {
        if allNotesWindowController == nil {
            allNotesWindowController = AllNotesWindowController(
                noteStore: noteStore,
                onOpenNote: { [weak self] id in
                    self?.openNote(noteID: id)
                },
                onDeleteNote: { [weak self] id in
                    self?.deleteNote(noteID: id)
                },
                onCreateNote: { [weak self] in
                    self?.createNewNote()
                },
                isWindowOpen: { [weak self] id in
                    self?.windowManager.isWindowOpen(for: id) ?? false
                }
            )
        }
        allNotesWindowController?.showWindow()
    }

    // MARK: - Export

    @objc func exportPlainText() {
        guard let noteID = currentNoteID(),
              let note = noteStore.notes[noteID],
              let window = NSApp.keyWindow else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = (note.title.isEmpty ? "Untitled" : note.title) + ".txt"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let text: String
                if let attrStr = try? NSAttributedString(
                    data: note.attributedBodyData,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                ) {
                    text = attrStr.string
                } else {
                    text = ""
                }
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                Log.persist.error("Export plain text failed: \(error.localizedDescription)")
            }
        }
    }

    @objc func exportRTF() {
        guard let noteID = currentNoteID(),
              let note = noteStore.notes[noteID],
              let window = NSApp.keyWindow else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.rtf]
        panel.nameFieldStringValue = (note.title.isEmpty ? "Untitled" : note.title) + ".rtf"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try note.attributedBodyData.write(to: url, options: .atomic)
            } catch {
                Log.persist.error("Export RTF failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Formatting proxy actions (routed to first responder)

    @objc func toggleBold(_ sender: Any?)         { NSApp.sendAction(#selector(NoteTextView.toggleBold(_:)), to: nil, from: sender) }
    @objc func toggleItalic(_ sender: Any?)        { NSApp.sendAction(#selector(NoteTextView.toggleItalic(_:)), to: nil, from: sender) }
    @objc func toggleUnderline(_ sender: Any?)     { NSApp.sendAction(#selector(NSText.underline(_:)), to: nil, from: sender) }
    @objc func increaseFontSize(_ sender: Any?)    { NSApp.sendAction(#selector(NoteTextView.increaseFontSize(_:)), to: nil, from: sender) }
    @objc func decreaseFontSize(_ sender: Any?)    { NSApp.sendAction(#selector(NoteTextView.decreaseFontSize(_:)), to: nil, from: sender) }
    @objc func alignTextLeft(_ sender: Any?)       { NSApp.sendAction(#selector(NSText.alignLeft(_:)), to: nil, from: sender) }
    @objc func alignTextCenter(_ sender: Any?)     { NSApp.sendAction(#selector(NSText.alignCenter(_:)), to: nil, from: sender) }
    @objc func alignTextRight(_ sender: Any?)      { NSApp.sendAction(#selector(NSText.alignRight(_:)), to: nil, from: sender) }
    @objc func toggleBullets(_ sender: Any?)       { NSApp.sendAction(#selector(NoteTextView.toggleBullets(_:)), to: nil, from: sender) }
    @objc func showTextColor(_ sender: Any?)       { NSApp.orderFrontColorPanel(sender) }
    @objc func bringNoteToFront(_ sender: Any?)    { NSApp.keyWindow?.makeKeyAndOrderFront(sender) }

    @objc func pinUnpinCurrentNote(_ sender: Any?) {
        guard let noteID = currentNoteID(),
              let ctrl = NSApp.keyWindow?.windowController as? NoteWindowController else { return }
        ctrl.noteContentViewDidClickPin(ctrl.window!.contentView as! NoteContentView)
    }

    @objc func changeThemeCurrentNote(_ sender: Any?) {
        guard let ctrl = NSApp.keyWindow?.windowController as? NoteWindowController,
              let contentView = ctrl.window?.contentView as? NoteContentView else { return }
        contentView.themeClicked(contentView.themeButton)
    }

    // MARK: - Helpers

    private func currentNoteID() -> UUID? {
        (NSApp.keyWindow?.windowController as? NoteWindowController)?.noteID
    }
}
