import AppKit

// MARK: - SettingsWindowController

/// A simple About/Settings panel — pure AppKit.
final class SettingsWindowController: NSWindowController {

    static let shared = SettingsWindowController()

    private init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.center()

        let contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))

        let config = NSImage.SymbolConfiguration(pointSize: 48, weight: .regular)
        let icon = NSImageView(image:
            NSImage(systemSymbolName: "note.text", accessibilityDescription: "Noted icon")?
                .withSymbolConfiguration(config) ?? NSImage()
        )
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(icon)

        let appName = NSTextField(labelWithString: "Noted")
        appName.font = .systemFont(ofSize: 20, weight: .semibold)
        appName.alignment = .center
        appName.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(appName)

        let version = NSTextField(labelWithString: "v1.0")
        version.font = .systemFont(ofSize: 13)
        version.textColor = .secondaryLabelColor
        version.alignment = .center
        version.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(version)

        let tagline = NSTextField(labelWithString: "A native macOS sticky notes app.")
        tagline.font = .systemFont(ofSize: 12)
        tagline.textColor = .secondaryLabelColor
        tagline.alignment = .center
        tagline.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tagline)

        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            icon.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 30),

            appName.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            appName.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 12),

            version.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            version.topAnchor.constraint(equalTo: appName.bottomAnchor, constant: 4),

            tagline.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            tagline.topAnchor.constraint(equalTo: version.bottomAnchor, constant: 4),
        ])

        window.contentView = contentView
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func showWindow() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
