import AppKit

// MARK: - NoteWindow

/// Borderless, transparent NSWindow that hosts a single sticky note.
final class NoteWindow: NSWindow {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        configure()
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        level = .normal
        collectionBehavior = [.managed, .participatesInCycle]
        minSize = NSSize(width: 180, height: 140)
        isReleasedWhenClosed = false
        tabbingMode = .disallowed
    }

    // Borderless windows must opt-in to become key/main.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
