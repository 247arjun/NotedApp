import AppKit
import NotedKit

// MARK: - NoteTextView

/// Custom NSTextView for the note body editor.
/// - Rich text editing with bold, italic, underline, font size, alignment, bullets.
/// - Prevents window drag when clicking inside the editor.
final class NoteTextView: NSTextView {

    /// Theme-aware default typing attributes.
    var defaultTypingAttributes: [NSAttributedString.Key: Any] = [:]

    // MARK: - Window drag prevention

    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: - Setup

    func configureForNote(theme: NoteTheme) {
        isRichText = true
        isEditable = true
        isSelectable = true
        allowsUndo = true
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]

        drawsBackground = false
        isAutomaticQuoteSubstitutionEnabled = true
        isAutomaticDashSubstitutionEnabled = true
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = true
        isGrammarCheckingEnabled = false

        // Find-in-note via the system find bar.
        usesFindBar = true
        isIncrementalSearchingEnabled = true

        textContainer?.widthTracksTextView = true
        textContainer?.containerSize = NSSize(
            width: 0, // will be set by scroll view
            height: CGFloat.greatestFiniteMagnitude
        )
        textContainerInset = NSSize(width: 12, height: 10)

        applyTheme(theme)
    }

    func applyTheme(_ theme: NoteTheme) {
        let settings = AppSettings.shared
        let font = settings.defaultFont
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        paragraphStyle.paragraphSpacing = 4

        defaultTypingAttributes = [
            .font: font,
            .foregroundColor: theme.bodyTextColor,
            .paragraphStyle: paragraphStyle,
        ]
        typingAttributes = defaultTypingAttributes
        insertionPointColor = theme.bodyTextColor
    }

    // MARK: - Accessibility

    override func accessibilityLabel() -> String? { "Note body" }

    // MARK: - Formatting Actions

    @objc func toggleBold(_ sender: Any?) {
        applyFontTrait(trait: .boldFontMask)
    }

    @objc func toggleItalic(_ sender: Any?) {
        applyFontTrait(trait: .italicFontMask)
    }

    @objc func increaseFontSize(_ sender: Any?) {
        modifyFontSize(delta: 2)
    }

    @objc func decreaseFontSize(_ sender: Any?) {
        modifyFontSize(delta: -2)
    }

    @objc func toggleBullets(_ sender: Any?) {
        guard let storage = textStorage else { return }
        let range = selectedRange()
        let paragraphRange = (string as NSString).paragraphRange(for: range)
        let text = (string as NSString).substring(with: paragraphRange)

        storage.beginEditing()

        let lines = text.components(separatedBy: "\n")
        let hasBullets = lines.contains(where: { $0.hasPrefix("•\t") || $0.hasPrefix("• ") })

        var replacement = ""
        for (i, line) in lines.enumerated() {
            var processedLine: String
            if hasBullets {
                // Remove bullet prefix
                if line.hasPrefix("•\t") {
                    processedLine = String(line.dropFirst(2))
                } else if line.hasPrefix("• ") {
                    processedLine = String(line.dropFirst(2))
                } else {
                    processedLine = line
                }
                // Remove head indent
            } else {
                // Add bullet prefix
                if line.isEmpty && i == lines.count - 1 {
                    processedLine = line // don't add bullet to trailing empty line
                } else {
                    processedLine = "•\t" + line
                }
            }
            replacement += processedLine
            if i < lines.count - 1 { replacement += "\n" }
        }

        // Replace text
        if shouldChangeText(in: paragraphRange, replacementString: replacement) {
            storage.replaceCharacters(in: paragraphRange, with: replacement)
            didChangeText()
        }

        // Apply paragraph style with indent
        let newParagraphRange = NSRange(location: paragraphRange.location, length: (replacement as NSString).length)
        let style = NSMutableParagraphStyle()
        if !hasBullets {
            style.headIndent = 20
            style.firstLineHeadIndent = 0
            let tabStop = NSTextTab(textAlignment: .left, location: 20)
            style.tabStops = [tabStop]
        } else {
            style.headIndent = 0
            style.firstLineHeadIndent = 0
            style.tabStops = []
        }
        style.lineSpacing = 2
        style.paragraphSpacing = 4
        storage.addAttribute(.paragraphStyle, value: style, range: newParagraphRange)

        storage.endEditing()
    }

    // MARK: - Private Formatting Helpers

    private func applyFontTrait(trait: NSFontTraitMask) {
        let range = selectedRange()
        let fm = NSFontManager.shared

        if range.length > 0 {
            guard let storage = textStorage else { return }
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
                guard let font = value as? NSFont else { return }
                let currentTraits = fm.traits(of: font)
                let newFont: NSFont
                if currentTraits.contains(trait) {
                    newFont = fm.convert(font, toNotHaveTrait: trait)
                } else {
                    newFont = fm.convert(font, toHaveTrait: trait)
                }
                storage.addAttribute(.font, value: newFont, range: attrRange)
            }
            storage.endEditing()
        } else {
            // Update typing attributes
            var attrs = typingAttributes
            if let font = attrs[.font] as? NSFont {
                let currentTraits = fm.traits(of: font)
                let newFont: NSFont
                if currentTraits.contains(trait) {
                    newFont = fm.convert(font, toNotHaveTrait: trait)
                } else {
                    newFont = fm.convert(font, toHaveTrait: trait)
                }
                attrs[.font] = newFont
                typingAttributes = attrs
            }
        }
    }

    private func modifyFontSize(delta: CGFloat) {
        let range = selectedRange()
        let minSize: CGFloat = 9
        let maxSize: CGFloat = 96

        if range.length > 0 {
            guard let storage = textStorage else { return }
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
                guard let font = value as? NSFont else { return }
                let newSize = max(minSize, min(maxSize, font.pointSize + delta))
                let newFont = NSFontManager.shared.convert(font, toSize: newSize)
                storage.addAttribute(.font, value: newFont, range: attrRange)
            }
            storage.endEditing()
        } else {
            var attrs = typingAttributes
            if let font = attrs[.font] as? NSFont {
                let newSize = max(minSize, min(maxSize, font.pointSize + delta))
                attrs[.font] = NSFontManager.shared.convert(font, toSize: newSize)
                typingAttributes = attrs
            }
        }
    }
}
