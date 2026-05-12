import SwiftUI
import UIKit
import NotedKit

// MARK: - RichTextEditor

/// SwiftUI wrapper around UITextView for RTF-backed rich text editing.
/// Mirrors the formatting actions of the macOS `NoteTextView`: bold, italic,
/// underline, font-size delta, bullets. Surfaces a custom keyboard accessory
/// bar with those actions.
struct RichTextEditor: UIViewRepresentable {

    @Binding var attributedData: Data
    let theme: NoteTheme

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = true
        tv.isSelectable = true
        tv.allowsEditingTextAttributes = true
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        tv.backgroundColor = .clear
        tv.delegate = context.coordinator
        tv.inputAccessoryView = context.coordinator.makeAccessoryBar()
        applyTheme(to: tv)
        loadAttributedString(into: tv)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        applyTheme(to: tv)
        // Only reload if the incoming bytes differ — avoid clobbering the
        // caret while the user types.
        let currentData = currentAttributedData(from: tv)
        if currentData != attributedData {
            let selected = tv.selectedRange
            loadAttributedString(into: tv)
            // Restore selection if possible
            if selected.location <= (tv.text as NSString).length {
                tv.selectedRange = selected
            }
        }
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    // MARK: - Helpers

    private func applyTheme(to tv: UITextView) {
        tv.font = AppSettings.shared.defaultFont
        tv.textColor = theme.bodyTextColor
        tv.tintColor = theme.controlTintColor
        tv.typingAttributes = [
            .font: AppSettings.shared.defaultFont,
            .foregroundColor: theme.bodyTextColor,
        ]
    }

    private func loadAttributedString(into tv: UITextView) {
        if attributedData.isEmpty {
            tv.attributedText = NSAttributedString(string: "", attributes: tv.typingAttributes)
            return
        }
        if let attr = try? NSAttributedString(
            data: attributedData,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) {
            tv.attributedText = attr
        }
    }

    fileprivate func currentAttributedData(from tv: UITextView) -> Data {
        let range = NSRange(location: 0, length: tv.attributedText.length)
        return (try? tv.attributedText.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )) ?? Data()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichTextEditor
        weak var textView: UITextView?

        init(parent: RichTextEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            self.textView = textView
            let data = parent.currentAttributedData(from: textView)
            // Push to binding (debounced inside NoteStore)
            DispatchQueue.main.async { [data] in
                self.parent.attributedData = data
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            self.textView = textView
        }

        // MARK: - Accessory Bar

        func makeAccessoryBar() -> UIToolbar {
            let bar = UIToolbar()
            bar.sizeToFit()

            func item(_ symbol: String, _ action: Selector) -> UIBarButtonItem {
                let cfg = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
                let img = UIImage(systemName: symbol, withConfiguration: cfg)
                return UIBarButtonItem(image: img, style: .plain, target: self, action: action)
            }

            let bold     = item("bold",          #selector(toggleBold))
            let italic   = item("italic",        #selector(toggleItalic))
            let under    = item("underline",     #selector(toggleUnderline))
            let bigger   = item("textformat.size.larger",  #selector(increaseSize))
            let smaller  = item("textformat.size.smaller", #selector(decreaseSize))
            let bullets  = item("list.bullet",   #selector(toggleBullets))
            let flex     = UIBarButtonItem(systemItem: .flexibleSpace)
            let done     = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
                self?.textView?.resignFirstResponder()
            })

            func fixed(_ w: CGFloat) -> UIBarButtonItem {
                let i = UIBarButtonItem(systemItem: .fixedSpace)
                i.width = w
                return i
            }

            bar.items = [bold, italic, under, fixed(12), smaller, bigger, fixed(12), bullets, flex, done]
            return bar
        }

        @objc fileprivate func toggleBold()      { applyTrait(.traitBold) }
        @objc fileprivate func toggleItalic()    { applyTrait(.traitItalic) }
        @objc fileprivate func toggleUnderline() { applyAttribute(.underlineStyle, on: NSUnderlineStyle.single.rawValue, offValue: 0) }
        @objc fileprivate func increaseSize()    { modifyFontSize(delta: 2) }
        @objc fileprivate func decreaseSize()    { modifyFontSize(delta: -2) }
        @objc fileprivate func toggleBullets()   { applyBullets() }

        // MARK: - Editing primitives

        private func applyTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
            guard let tv = textView, let storage = tv.textStorage as NSMutableAttributedString? else { return }
            let range = tv.selectedRange
            guard range.length > 0 else {
                // Toggle typing attributes if no selection
                let current = (tv.typingAttributes[.font] as? UIFont) ?? AppSettings.shared.defaultFont
                let newFont = toggle(font: current, trait: trait)
                var attrs = tv.typingAttributes
                attrs[.font] = newFont
                tv.typingAttributes = attrs
                return
            }
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range) { value, sub, _ in
                let base = (value as? UIFont) ?? AppSettings.shared.defaultFont
                storage.addAttribute(.font, value: toggle(font: base, trait: trait), range: sub)
            }
            storage.endEditing()
            triggerChange()
        }

        private func toggle(font: UIFont, trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
            var traits = font.fontDescriptor.symbolicTraits
            if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
            if let desc = font.fontDescriptor.withSymbolicTraits(traits) {
                return UIFont(descriptor: desc, size: font.pointSize)
            }
            return font
        }

        private func applyAttribute(_ key: NSAttributedString.Key, on onValue: Any, offValue: Any) {
            guard let tv = textView, let storage = tv.textStorage as NSMutableAttributedString? else { return }
            let range = tv.selectedRange
            guard range.length > 0 else { return }
            storage.beginEditing()
            let existing = storage.attribute(key, at: range.location, effectiveRange: nil)
            let isOn: Bool = {
                if let n = existing as? Int { return n != 0 }
                if let n = existing as? NSNumber { return n.intValue != 0 }
                return existing != nil
            }()
            storage.addAttribute(key, value: isOn ? offValue : onValue, range: range)
            storage.endEditing()
            triggerChange()
        }

        private func modifyFontSize(delta: CGFloat) {
            guard let tv = textView, let storage = tv.textStorage as NSMutableAttributedString? else { return }
            let range = tv.selectedRange
            if range.length == 0 {
                let current = (tv.typingAttributes[.font] as? UIFont) ?? AppSettings.shared.defaultFont
                var attrs = tv.typingAttributes
                attrs[.font] = current.withSize(max(8, current.pointSize + delta))
                tv.typingAttributes = attrs
                return
            }
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range) { value, sub, _ in
                let base = (value as? UIFont) ?? AppSettings.shared.defaultFont
                storage.addAttribute(.font, value: base.withSize(max(8, base.pointSize + delta)), range: sub)
            }
            storage.endEditing()
            triggerChange()
        }

        private func applyBullets() {
            guard let tv = textView, let storage = tv.textStorage as NSMutableAttributedString? else { return }
            let text = tv.text ?? ""
            let selRange = tv.selectedRange
            let nsText = text as NSString
            let paraRange = nsText.paragraphRange(for: selRange)
            let segment = nsText.substring(with: paraRange)
            let lines = segment.components(separatedBy: "\n")
            let hasBullets = lines.contains { $0.hasPrefix("•\t") || $0.hasPrefix("• ") }

            var replacement = ""
            for (i, line) in lines.enumerated() {
                var processed = line
                if hasBullets {
                    if processed.hasPrefix("•\t") { processed = String(processed.dropFirst(2)) }
                    else if processed.hasPrefix("• ") { processed = String(processed.dropFirst(2)) }
                } else {
                    if !(processed.isEmpty && i == lines.count - 1) {
                        processed = "•\t" + processed
                    }
                }
                replacement += processed
                if i < lines.count - 1 { replacement += "\n" }
            }

            storage.beginEditing()
            let attrs = tv.typingAttributes
            storage.replaceCharacters(in: paraRange, with: NSAttributedString(string: replacement, attributes: attrs))
            storage.endEditing()
            triggerChange()
        }

        private func triggerChange() {
            guard let tv = textView else { return }
            let data = parent.currentAttributedData(from: tv)
            DispatchQueue.main.async { [data] in self.parent.attributedData = data }
        }
    }
}
