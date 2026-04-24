import AppKit

// MARK: - NoteContentViewDelegate

@MainActor
protocol NoteContentViewDelegate: AnyObject {
    func noteContentView(_ view: NoteContentView, didCommitTitle title: String)
    func noteContentViewDidClickClose(_ view: NoteContentView)
    func noteContentViewDidClickDelete(_ view: NoteContentView)
    func noteContentViewDidClickPin(_ view: NoteContentView)
    func noteContentView(_ view: NoteContentView, didSelectTheme themeID: String)
}

// MARK: - NoteContentView

/// Root AppKit view for a single note window.
///
/// Layout:
/// ```
/// ┌──────────────────────────────────────┐
/// │  HEADER (34 pt)                      │
/// │  [Title       ]  [Pin][🎨][✕][🗑]   │
/// ├──────────────────────────────────────┤
/// │                                      │
/// │  NSScrollView ▸ NoteTextView         │
/// │                                      │
/// │                                ╱╱╱   │  ← resize handle
/// └──────────────────────────────────────┘
/// ```
final class NoteContentView: NSView {

    // MARK: - Public properties

    let noteID: UUID
    private(set) var theme: NoteTheme
    private(set) var isPinned: Bool = false

    weak var delegate: NoteContentViewDelegate?

    // Subviews
    let headerView = NSView()
    let titleField: NSTextField
    let closeButton: NSButton
    let deleteButton: NSButton
    let pinButton: NSButton
    let themeButton: NSButton
    let editorScrollView: NSScrollView
    let textView: NoteTextView
    let resizeHandle: ResizeHandleView

    /// When true, hides the header control buttons (pin/theme/delete/close)
    /// — used in the All Notes detail pane where controls live in the toolbar.
    var hidesHeaderControls: Bool = false {
        didSet {
            closeButton.isHidden = hidesHeaderControls
            deleteButton.isHidden = hidesHeaderControls
            pinButton.isHidden = hidesHeaderControls
            themeButton.isHidden = hidesHeaderControls
        }
    }

    // Theme popover
    private var themePopover: NSPopover?

    // MARK: - Init

    init(noteID: UUID, theme: NoteTheme) {
        self.noteID = noteID
        self.theme = theme

        // Title field
        titleField = NSTextField()
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.isEditable = true
        titleField.isBezeled = false
        titleField.focusRingType = .none
        titleField.lineBreakMode = .byTruncatingTail
        titleField.cell?.truncatesLastVisibleLine = true
        titleField.cell?.isScrollable = false
        titleField.cell?.wraps = false
        titleField.maximumNumberOfLines = 1
        titleField.placeholderString = "Untitled"
        titleField.font = .systemFont(ofSize: 14, weight: .semibold)
        titleField.setAccessibilityLabel("Note title")

        // Buttons
        closeButton  = Self.makeHeaderButton(symbolName: "xmark", label: "Close note")
        deleteButton = Self.makeHeaderButton(symbolName: "trash", label: "Delete note")
        pinButton    = Self.makeHeaderButton(symbolName: "pin", label: "Pin note")
        themeButton  = Self.makeHeaderButton(symbolName: "paintpalette", label: "Change note color")

        // Editor
        editorScrollView = NSScrollView()
        textView = NoteTextView()

        // Resize handle
        resizeHandle = ResizeHandleView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))

        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        setupSubviews()
        setupConstraints()
        applyTheme(theme)
        wireActions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Theme

    func applyTheme(_ newTheme: NoteTheme) {
        theme = newTheme

        // Background
        layer?.backgroundColor = newTheme.bodyBackgroundColor.cgColor
        headerView.layer?.backgroundColor = newTheme.headerBackgroundColor.cgColor

        // Title
        titleField.textColor = newTheme.titleTextColor
        if let cell = titleField.cell as? NSTextFieldCell {
            let placeholder = NSAttributedString(
                string: "Untitled",
                attributes: [
                    .foregroundColor: newTheme.placeholderTextColor,
                    .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                ]
            )
            cell.placeholderAttributedString = placeholder
        }

        // Controls
        closeButton.contentTintColor  = newTheme.controlTintColor
        deleteButton.contentTintColor = newTheme.controlTintColor
        pinButton.contentTintColor    = newTheme.controlTintColor
        themeButton.contentTintColor  = newTheme.controlTintColor

        // Editor
        textView.applyTheme(newTheme)

        // Resize handle
        resizeHandle.theme = newTheme

        needsDisplay = true
    }

    func updatePinState(_ pinned: Bool) {
        isPinned = pinned
        let symbolName = pinned ? "pin.fill" : "pin"
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        pinButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: pinned ? "Unpin note" : "Pin note")?
            .withSymbolConfiguration(config)
        pinButton.setAccessibilityLabel(pinned ? "Unpin note" : "Pin note")
        pinButton.setAccessibilityValue(pinned ? "pinned" : "unpinned")
    }

    // MARK: - Text Content

    func loadBody(from data: Data) {
        guard !data.isEmpty else { return }
        do {
            let attrStr = try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
            textView.textStorage?.setAttributedString(attrStr)
        } catch {
            Log.restore.error("Failed to decode body for note \(self.noteID): \(error.localizedDescription)")
            // Graceful fallback: leave editor empty.
        }
    }

    // MARK: - Setup

    private func setupSubviews() {
        // Header
        headerView.wantsLayer = true
        addSubview(headerView)

        titleField.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleField)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(closeButton)

        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(deleteButton)

        pinButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(pinButton)

        themeButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(themeButton)

        // Editor scroll view
        editorScrollView.hasVerticalScroller = true
        editorScrollView.hasHorizontalScroller = false
        editorScrollView.autohidesScrollers = true
        editorScrollView.drawsBackground = false
        editorScrollView.contentView.drawsBackground = false

        textView.configureForNote(theme: theme)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        editorScrollView.documentView = textView
        addSubview(editorScrollView)

        // Resize handle
        addSubview(resizeHandle)
    }

    private func setupConstraints() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        editorScrollView.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // Header
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 34),

            // Title field
            titleField.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            titleField.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: pinButton.leadingAnchor, constant: -8),

            // Control cluster (right-to-left): [Pin][Theme][Delete][Close]
            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),

            deleteButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            deleteButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 20),
            deleteButton.heightAnchor.constraint(equalToConstant: 20),

            themeButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),
            themeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            themeButton.widthAnchor.constraint(equalToConstant: 20),
            themeButton.heightAnchor.constraint(equalToConstant: 20),

            pinButton.trailingAnchor.constraint(equalTo: themeButton.leadingAnchor, constant: -8),
            pinButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            pinButton.widthAnchor.constraint(equalToConstant: 20),
            pinButton.heightAnchor.constraint(equalToConstant: 20),

            // Editor
            editorScrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            editorScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            editorScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            editorScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Resize handle
            resizeHandle.trailingAnchor.constraint(equalTo: trailingAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: bottomAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: 28),
            resizeHandle.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    private func wireActions() {
        closeButton.target = self
        closeButton.action = #selector(closeClicked)

        deleteButton.target = self
        deleteButton.action = #selector(deleteClicked)

        pinButton.target = self
        pinButton.action = #selector(pinClicked)

        themeButton.target = self
        themeButton.action = #selector(themeClicked)

        titleField.delegate = self
    }

    // MARK: - Actions

    @objc private func closeClicked(_ sender: Any?) {
        delegate?.noteContentViewDidClickClose(self)
    }

    @objc private func deleteClicked(_ sender: Any?) {
        delegate?.noteContentViewDidClickDelete(self)
    }

    @objc private func pinClicked(_ sender: Any?) {
        delegate?.noteContentViewDidClickPin(self)
    }

    @objc func themeClicked(_ sender: NSButton) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 200, height: 50)

        let pickerVC = ThemePickerViewController(currentThemeID: theme.id) { [weak self, weak popover] selectedID in
            guard let self else { return }
            popover?.performClose(nil)
            self.delegate?.noteContentView(self, didSelectTheme: selectedID)
        }
        popover.contentViewController = pickerVC
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        themePopover = popover
    }

    // MARK: - Helpers

    private static func makeHeaderButton(symbolName: String, label: String) -> NSButton {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)?
            .withSymbolConfiguration(config) ?? NSImage()
        let button = NSButton(image: image, target: nil, action: nil)
        button.isBordered = false
        button.bezelStyle = .inline
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel(label)
        button.setAccessibilityRole(.button)
        (button.cell as? NSButtonCell)?.highlightsBy = .contentsCellMask
        return button
    }
}

// MARK: - NSTextFieldDelegate (Title)

extension NoteContentView: NSTextFieldDelegate {

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Return → commit title, move focus to body editor
            window?.makeFirstResponder(self.textView)
            delegate?.noteContentView(self, didCommitTitle: titleField.stringValue)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // Escape → move focus to body editor without committing changes
            window?.makeFirstResponder(self.textView)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        delegate?.noteContentView(self, didCommitTitle: titleField.stringValue)
    }
}
