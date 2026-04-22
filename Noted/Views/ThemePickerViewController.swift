import AppKit

// MARK: - ThemePickerViewController

/// Pure AppKit popover content: a row of colored circles for theme selection.
final class ThemePickerViewController: NSViewController {

    var currentThemeID: String
    var onSelect: ((String) -> Void)?

    init(currentThemeID: String, onSelect: @escaping (String) -> Void) {
        self.currentThemeID = currentThemeID
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 50))

        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 10
        stackView.alignment = .centerY
        stackView.translatesAutoresizingMaskIntoConstraints = false

        for theme in ThemeRegistry.allThemes {
            let button = ThemeSwatchButton(theme: theme, isSelected: theme.id == currentThemeID)
            button.target = self
            button.action = #selector(swatchClicked(_:))
            stackView.addArrangedSubview(button)
        }

        container.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        self.view = container
    }

    @objc private func swatchClicked(_ sender: ThemeSwatchButton) {
        onSelect?(sender.themeID)
    }
}

// MARK: - ThemeSwatchButton

/// A single colored circle button representing a theme.
final class ThemeSwatchButton: NSButton {

    let themeID: String
    private let swatchColor: NSColor
    private let isSelectedTheme: Bool

    init(theme: NoteTheme, isSelected: Bool) {
        self.themeID = theme.id
        self.swatchColor = theme.headerBackgroundColor
        self.isSelectedTheme = isSelected
        super.init(frame: NSRect(x: 0, y: 0, width: 30, height: 30))

        isBordered = false
        title = ""
        bezelStyle = .inline
        setButtonType(.momentaryPushIn)
        setAccessibilityLabel(theme.displayName)
        setAccessibilityRole(.button)
        if isSelected {
            setAccessibilityValue("selected")
        }

        widthAnchor.constraint(equalToConstant: 30).isActive = true
        heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let circleRect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(ovalIn: circleRect)
        swatchColor.setFill()
        path.fill()

        if isSelectedTheme {
            let ringRect = bounds.insetBy(dx: 0, dy: 0)
            let ring = NSBezierPath(ovalIn: ringRect)
            ring.lineWidth = 2.5
            NSColor.controlTextColor.withAlphaComponent(0.7).setStroke()
            ring.stroke()
        }
    }
}
