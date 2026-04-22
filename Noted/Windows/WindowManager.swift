import AppKit

// MARK: - WindowManager

/// Creates, tracks, and manages NoteWindowController instances.
@MainActor
final class WindowManager {

    private var controllers: [UUID: NoteWindowController] = [:]
    private weak var noteStore: NoteStore?

    /// Cascade offset accumulator for new note positioning.
    private var cascadePoint: NSPoint = .zero

    init(noteStore: NoteStore) {
        self.noteStore = noteStore

        // Observe window close notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowClose(_:)),
            name: .noteWindowDidClose,
            object: nil
        )

        // Observe window delete requests
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDeleteRequest(_:)),
            name: .noteWindowDidRequestDelete,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public

    var openWindowCount: Int { controllers.count }

    func isWindowOpen(for noteID: UUID) -> Bool {
        controllers[noteID] != nil
    }

    /// Open (or bring to front) a window for the given note.
    func openWindow(for noteID: UUID) {
        guard let store = noteStore, let note = store.notes[noteID] else {
            Log.window.error("Cannot open window: note \(noteID) not found in store")
            return
        }

        // If already open, bring to front
        if let existing = controllers[noteID] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let theme = ThemeRegistry.theme(for: note.themeID)
        let frame = validatedFrame(note.frame)

        let controller = NoteWindowController(
            noteID: noteID,
            noteStore: store,
            frame: frame.cgRect,
            theme: theme
        )
        controller.loadContent(from: note)
        controllers[noteID] = controller

        controller.window?.makeKeyAndOrderFront(nil)

        // Mark as open
        store.markClosed(noteID: noteID, isClosed: false)

        Log.window.debug("Opened window for note \(noteID)")
    }

    /// Open a new note with a cascaded position.
    func openNewNoteWindow(noteID: UUID) {
        guard let store = noteStore, var note = store.notes[noteID] else { return }

        // Cascade from last position
        let frame = nextCascadedFrame()
        note.frame = PersistedRect(from: frame)
        store.updateFrame(noteID: noteID, frame: note.frame)

        let theme = ThemeRegistry.theme(for: note.themeID)
        let controller = NoteWindowController(
            noteID: noteID,
            noteStore: store,
            frame: frame,
            theme: theme
        )
        controller.loadContent(from: note)
        controllers[noteID] = controller

        // Use NSWindow cascading
        if let window = controller.window {
            cascadePoint = window.cascadeTopLeft(from: cascadePoint)
            window.makeKeyAndOrderFront(nil)
        }

        // Focus editor
        controller.focusEditor()

        store.markClosed(noteID: noteID, isClosed: false)
        Log.window.debug("Opened new note window for \(noteID)")
    }

    /// Close a window without deleting the note.
    func closeWindow(for noteID: UUID) {
        controllers[noteID]?.window?.close()
        // The close notification handler will remove the controller.
    }

    /// Restore all open note windows after launch.
    func restoreAllWindows() {
        guard let store = noteStore else { return }
        let openNotes = store.notes.values.filter { !$0.isClosed }
            .sorted(by: { $0.createdAt < $1.createdAt })

        for note in openNotes {
            openWindow(for: note.id)
        }
        Log.restore.info("Restored \(openNotes.count) note windows")
    }

    /// Close all windows (for quit or testing).
    func closeAllWindows() {
        for (_, controller) in controllers {
            controller.window?.close()
        }
    }

    // MARK: - Private

    @objc private func handleWindowClose(_ notification: Notification) {
        guard let noteID = notification.object as? UUID else { return }
        controllers.removeValue(forKey: noteID)
    }

    @objc private func handleWindowDeleteRequest(_ notification: Notification) {
        guard let noteID = notification.object as? UUID else { return }
        // Close the window without triggering the normal close-mark flow
        if let controller = controllers.removeValue(forKey: noteID) {
            // Remove delegate to prevent windowWillClose from marking as closed
            controller.window?.delegate = nil
            controller.window?.close()
        }
        noteStore?.deleteNote(noteID: noteID)
    }

    private func nextCascadedFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return PersistedRect.default.cgRect
        }
        let screenFrame = screen.visibleFrame

        // Start cascade from upper-left area of screen
        if cascadePoint == .zero {
            cascadePoint = NSPoint(
                x: screenFrame.minX + 80,
                y: screenFrame.maxY - 80
            )
        }

        let width: CGFloat = 320
        let height: CGFloat = 320
        let origin = NSPoint(
            x: cascadePoint.x,
            y: cascadePoint.y - height
        )
        return NSRect(origin: origin, size: NSSize(width: width, height: height))
    }

    /// Validate a persisted frame is on-screen; clamp if not (§22.3).
    private func validatedFrame(_ frame: PersistedRect) -> PersistedRect {
        let rect = frame.cgRect
        let screens = NSScreen.screens

        // Check if at least part of the note is visible on any screen
        let isVisible = screens.contains { screen in
            screen.visibleFrame.intersects(rect)
        }

        if isVisible {
            return frame
        }

        // Offscreen → clamp to main screen
        guard let mainScreen = NSScreen.main else { return frame }
        let visible = mainScreen.visibleFrame

        var clamped = rect
        clamped.size.width  = min(clamped.width, visible.width)
        clamped.size.height = min(clamped.height, visible.height)
        clamped.origin.x = max(visible.minX, min(clamped.origin.x, visible.maxX - clamped.width))
        clamped.origin.y = max(visible.minY, min(clamped.origin.y, visible.maxY - clamped.height))

        Log.restore.info("Clamped offscreen frame for note to \(clamped.debugDescription)")
        return PersistedRect(from: clamped)
    }
}
