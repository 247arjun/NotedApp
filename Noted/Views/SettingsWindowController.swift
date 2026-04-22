import AppKit

// MARK: - SettingsWindowController

/// Settings panel using NSGridView for clean two-column form layout.
@MainActor
final class SettingsWindowController: NSWindowController {

    static let shared = SettingsWindowController()

    // MARK: - Controls

    private let saveLocationLabel = NSTextField(labelWithString: "")
    private let themePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let launchPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fontNameLabel = NSTextField(labelWithString: "")
    private let fontSizeStepper = NSStepper()
    private let fontSizeField = NSTextField(labelWithString: "")

    private init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        buildUI()
        loadCurrentValues()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func showWindow() {
        loadCurrentValues()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Build UI

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        // Build all rows: [label, value] pairs with section headers as merged rows.
        var rows: [[NSView]] = []

        // ── Storage ──
        rows.append([makeSectionHeader("Storage")])
        rows.append([makeLabel("Save location:"), makeLocationRow()])

        // ── Appearance ──
        rows.append([makeSectionHeader("Appearance")])
        rows.append([makeLabel("Default theme:"), themePopUpSetup()])

        // ── Editor ──
        rows.append([makeSectionHeader("Editor")])
        rows.append([makeLabel("Default font:"), makeFontRow()])
        rows.append([makeLabel("Default size:"), makeSizeRow()])

        // ── General ──
        rows.append([makeSectionHeader("General")])
        rows.append([makeLabel("On launch:"), launchPopUpSetup()])

        let grid = NSGridView(views: rows)
        grid.translatesAutoresizingMaskIntoConstraints = false

        // Column config
        grid.column(at: 0).xPlacement = .trailing   // labels right-aligned
        grid.column(at: 1).xPlacement = .leading     // values left-aligned
        grid.column(at: 0).width = 120

        // Row spacing
        grid.rowSpacing = 10
        grid.columnSpacing = 12

        // Merge section header rows across both columns
        for (i, row) in rows.enumerated() {
            if row.count == 1 {
                grid.cell(atColumnIndex: 0, rowIndex: i).xPlacement = .leading
                grid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: i, length: 1))
                // Add top padding before section headers (except first)
                if i > 0 {
                    grid.row(at: i).topPadding = 12
                }
            }
        }

        contentView.addSubview(grid)

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
        ])
    }

    // MARK: - Helpers

    private func makeSectionHeader(_ title: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .bold)
        label.textColor = .labelColor
        stack.addArrangedSubview(label)

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(sep)
        sep.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        return stack
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.alignment = .right
        return label
    }

    // MARK: - Row Builders

    private func makeLocationRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8

        saveLocationLabel.isEditable = false
        saveLocationLabel.isBordered = false
        saveLocationLabel.drawsBackground = false
        saveLocationLabel.textColor = .secondaryLabelColor
        saveLocationLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        saveLocationLabel.lineBreakMode = .byTruncatingMiddle
        saveLocationLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        saveLocationLabel.translatesAutoresizingMaskIntoConstraints = false
        saveLocationLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true

        let chooseBtn = NSButton(title: "Choose…", target: self, action: #selector(chooseSaveLocation))
        chooseBtn.bezelStyle = .rounded
        let resetBtn = NSButton(title: "Reset", target: self, action: #selector(resetSaveLocation))
        resetBtn.bezelStyle = .rounded

        row.addArrangedSubview(saveLocationLabel)
        row.addArrangedSubview(chooseBtn)
        row.addArrangedSubview(resetBtn)
        return row
    }

    private func themePopUpSetup() -> NSView {
        themePopUp.removeAllItems()
        for theme in ThemeRegistry.allThemes {
            themePopUp.addItem(withTitle: theme.displayName)
            themePopUp.lastItem?.representedObject = theme.id
        }
        themePopUp.target = self
        themePopUp.action = #selector(themeChanged)
        themePopUp.translatesAutoresizingMaskIntoConstraints = false
        themePopUp.widthAnchor.constraint(equalToConstant: 160).isActive = true
        return themePopUp
    }

    private func makeFontRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8

        fontNameLabel.isEditable = false
        fontNameLabel.isBordered = false
        fontNameLabel.drawsBackground = false
        fontNameLabel.font = .systemFont(ofSize: 13)

        let fontBtn = NSButton(title: "Change…", target: self, action: #selector(chooseFont(_:)))
        fontBtn.bezelStyle = .rounded

        row.addArrangedSubview(fontNameLabel)
        row.addArrangedSubview(fontBtn)
        return row
    }

    private func makeSizeRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 4
        row.alignment = .centerY

        fontSizeField.isEditable = false
        fontSizeField.isBordered = false
        fontSizeField.drawsBackground = false
        fontSizeField.alignment = .right
        fontSizeField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        fontSizeField.translatesAutoresizingMaskIntoConstraints = false
        fontSizeField.widthAnchor.constraint(equalToConstant: 30).isActive = true

        fontSizeStepper.minValue = 9
        fontSizeStepper.maxValue = 48
        fontSizeStepper.increment = 1
        fontSizeStepper.valueWraps = false
        fontSizeStepper.target = self
        fontSizeStepper.action = #selector(fontSizeChanged)

        let ptLabel = NSTextField(labelWithString: "pt")
        ptLabel.font = .systemFont(ofSize: 13)
        ptLabel.textColor = .secondaryLabelColor

        row.addArrangedSubview(fontSizeField)
        row.addArrangedSubview(fontSizeStepper)
        row.addArrangedSubview(ptLabel)
        return row
    }

    private func launchPopUpSetup() -> NSView {
        launchPopUp.removeAllItems()
        for behavior in LaunchBehavior.allCases {
            launchPopUp.addItem(withTitle: behavior.displayName)
            launchPopUp.lastItem?.tag = behavior.rawValue
        }
        launchPopUp.target = self
        launchPopUp.action = #selector(launchBehaviorChanged)
        launchPopUp.translatesAutoresizingMaskIntoConstraints = false
        launchPopUp.widthAnchor.constraint(equalToConstant: 260).isActive = true
        return launchPopUp
    }

    // MARK: - Load Values

    private func loadCurrentValues() {
        let settings = AppSettings.shared
        saveLocationLabel.stringValue = settings.saveLocationDisplayPath

        let themeIdx = ThemeRegistry.allThemes.firstIndex(where: { $0.id == settings.defaultThemeID }) ?? 0
        themePopUp.selectItem(at: themeIdx)

        fontNameLabel.stringValue = settings.defaultFont.displayName ?? settings.defaultFontName
        fontSizeField.stringValue = "\(Int(settings.defaultFontSize))"
        fontSizeStepper.doubleValue = Double(settings.defaultFontSize)

        launchPopUp.selectItem(withTag: settings.launchBehavior.rawValue)
    }

    // MARK: - Actions

    @objc private func chooseSaveLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder to store your notes"

        guard let window = self.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.migrateTo(url: url)
        }
    }

    @objc private func resetSaveLocation() {
        let defaultDir = AppSettings.shared.defaultSaveDirectory
        if AppSettings.shared.customSaveLocationURL != nil {
            migrateTo(url: defaultDir)
            AppSettings.shared.customSaveLocationURL = nil
        }
        saveLocationLabel.stringValue = AppSettings.shared.saveLocationDisplayPath
    }

    @objc private func themeChanged() {
        guard let selectedID = themePopUp.selectedItem?.representedObject as? String else { return }
        AppSettings.shared.defaultThemeID = selectedID
    }

    @objc private func launchBehaviorChanged() {
        let tag = launchPopUp.selectedItem?.tag ?? 0
        AppSettings.shared.launchBehavior = LaunchBehavior(rawValue: tag) ?? .allNotesAndRestore
    }

    @objc private func chooseFont(_ sender: Any?) {
        let fm = NSFontManager.shared
        fm.target = self
        fm.action = #selector(fontPanelDidChangeFont(_:))
        fm.setSelectedFont(AppSettings.shared.defaultFont, isMultiple: false)
        fm.orderFrontFontPanel(sender)
    }

    @objc private func fontPanelDidChangeFont(_ sender: NSFontManager) {
        let newFont = sender.convert(AppSettings.shared.defaultFont)
        AppSettings.shared.defaultFontName = newFont.fontName
        fontNameLabel.stringValue = newFont.displayName ?? newFont.fontName
    }

    @objc private func fontSizeChanged() {
        let size = CGFloat(fontSizeStepper.doubleValue)
        AppSettings.shared.defaultFontSize = size
        fontSizeField.stringValue = "\(Int(size))"
    }

    // MARK: - Migration

    private func migrateTo(url: URL) {
        guard let persistence = AppCoordinator.shared.persistenceService as? FilePersistenceService else { return }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            try persistence.migrateNotes(to: url)
            AppSettings.shared.customSaveLocationURL = url
            saveLocationLabel.stringValue = AppSettings.shared.saveLocationDisplayPath
            Log.persist.info("Save location changed to \(url.path)")
        } catch {
            let alert = NSAlert()
            alert.messageText = "Migration Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            if let w = window { alert.beginSheetModal(for: w) }
        }
    }
}
