import AppKit

// MARK: - AllNotesWindowController

/// Manages the "All Notes" utility window — pure AppKit with Liquid Glass.
///
/// Window configuration for Liquid Glass:
/// - `.fullSizeContentView` lets content extend behind the title bar
/// - `.titlebarAppearsTransparent` merges the toolbar into the glass effect
/// - `.unifiedTitleAndToolbar` creates a single unified glass bar
/// - The content view controller uses `NSVisualEffectView` with `.sidebar` material
final class AllNotesWindowController: NSWindowController {

    convenience init(noteStore: NoteStore, onOpenNote: @escaping (UUID) -> Void, onDeleteNote: @escaping (UUID) -> Void, onCreateNote: @escaping () -> Void, isWindowOpen: @escaping (UUID) -> Bool) {
        let viewController = AllNotesViewController(noteStore: noteStore)
        viewController.onOpenNote = onOpenNote
        viewController.onDeleteNote = onDeleteNote
        viewController.onCreateNote = onCreateNote
        viewController.isWindowOpen = isWindowOpen

        let window = NSWindow(contentViewController: viewController)
        window.title = "All Notes"
        window.styleMask = [
            .titled,
            .closable,
            .resizable,
            .miniaturizable,
            .fullSizeContentView,          // Content extends behind title bar
        ]
        window.titlebarAppearsTransparent = true   // Glass title bar
        window.titleVisibility = .hidden           // Hide title text, toolbar owns the space
        window.setContentSize(NSSize(width: 400, height: 500))
        window.minSize = NSSize(width: 300, height: 250)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("AllNotesWindow")
        window.tabbingMode = .disallowed

        self.init(window: window)
    }

    func showWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
