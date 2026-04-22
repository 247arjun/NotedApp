import AppKit

// MARK: - ResizeHandleView

/// Bottom-right resize affordance for borderless note windows.
/// Draws subtle diagonal grip lines and handles mouse tracking.
final class ResizeHandleView: NSView {

    var theme: NoteTheme? { didSet { needsDisplay = true } }

    // Tracking state
    private var initialMouseLocation: NSPoint = .zero
    private var initialWindowFrame: NSRect = .zero

    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: NSCursor(image: NSImage(size: .zero), hotSpot: .zero))
        // Use a system diagonal resize cursor
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let color = (theme?.foldedCornerColor ?? NSColor.gray).withAlphaComponent(0.6)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1.0)
        ctx.setLineCap(.round)

        let s = bounds.size
        // Three diagonal grip lines (bottom-right corner; macOS origin = bottom-left)
        for i in 0..<3 {
            let offset = CGFloat(i) * 4.0 + 4.0
            ctx.move(to: CGPoint(x: s.width - offset, y: 0))
            ctx.addLine(to: CGPoint(x: s.width, y: offset))
        }
        ctx.strokePath()
    }

    // MARK: - Mouse Tracking

    override func mouseDown(with event: NSEvent) {
        initialMouseLocation = NSEvent.mouseLocation
        initialWindowFrame = window?.frame ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - initialMouseLocation.x
        let dy = current.y - initialMouseLocation.y

        let newWidth  = max(window.minSize.width, initialWindowFrame.width + dx)
        let newHeight = max(window.minSize.height, initialWindowFrame.height - dy)

        var frame = initialWindowFrame
        frame.size.width = newWidth
        frame.size.height = newHeight
        // Keep top-left corner fixed (macOS coords: origin is bottom-left)
        frame.origin.y = initialWindowFrame.maxY - newHeight

        window.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        // Notify window controller of frame change
        if let noteWindow = window, let ctrl = noteWindow.windowController as? NoteWindowController {
            ctrl.windowDidEndResize()
        }
    }
}
