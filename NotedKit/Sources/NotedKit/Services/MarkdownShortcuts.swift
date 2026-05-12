import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - MarkdownShortcuts

/// Inline markdown shortcut detection for live editor input.
///
/// Call `processEdit(in:editedRange:typedCharacter:baseFont:)` from a text
/// view's "did change" hook. When the user types the closing token of a
/// markdown pattern (e.g. the second `*` of `**bold**`), the engine rewrites
/// the matched range into attributed text and removes the markers — same
/// behavior as Apple Notes / Bear / Drafts.
///
/// V1 patterns: `**bold**`, `__bold__`, `*italic*`, `_italic_`,
/// `~~strikethrough~~`, ``` `code` ```.
public enum MarkdownShortcuts {

    /// Result of processing an edit. If `replaced` is true the textview
    /// should refresh its selection (caret moves to end of new attributed
    /// text). Otherwise it's a no-op.
    public struct Result: Sendable {
        public let replaced: Bool
        /// New caret location to set after the edit, in the storage's final
        /// length space.
        public let newCaret: Int
        public static let noChange = Result(replaced: false, newCaret: -1)
    }

    /// Process the most recent edit. `editedRange` is the range of text that
    /// was just inserted (typically length 1 for a single typed character).
    ///
    /// - Parameters:
    ///   - storage: The text storage being edited.
    ///   - editedRange: Range of the just-inserted text in `storage`.
    ///   - baseFont: Font to use for "normal" text in this editor — used as
    ///     the basis for bold/italic transformations.
    @discardableResult
    public static func processEdit(
        in storage: NSMutableAttributedString,
        editedRange: NSRange,
        baseFont: PlatformFont
    ) -> Result {
        guard editedRange.length > 0,
              editedRange.location + editedRange.length <= storage.length else {
            return .noChange
        }

        // Try each pattern in priority order. We anchor on the just-typed
        // character at the END of editedRange, then scan backward to find the
        // opening marker.
        let endLoc = editedRange.location + editedRange.length

        // Slice of the full text up to the caret — patterns only match if
        // their closing token is what was just typed.
        let nsText = storage.string as NSString
        let upTo = nsText.substring(to: endLoc)

        for pattern in patterns {
            if let match = pattern.match(in: upTo) {
                return apply(pattern: pattern, match: match, storage: storage, baseFont: baseFont)
            }
        }
        return .noChange
    }

    // MARK: - Patterns

    private struct Pattern: Sendable {
        let marker: String                // e.g. "**" or "*" or "`"
        /// Apply the styling to a font/run. Returns the updated attribute set.
        let restyle: @Sendable (NSMutableAttributedString, NSRange, PlatformFont) -> Void

        /// Find a match anchored at the very end of `text`. Returns the range
        /// (inside the original `storage.string`) of the entire `**...**`
        /// match including markers.
        func match(in text: String) -> NSRange? {
            let marker = self.marker
            let nsText = text as NSString
            // The closing marker must be exactly at the end.
            guard nsText.length >= 2 * marker.count else { return nil }
            let closeRange = NSRange(location: nsText.length - marker.count, length: marker.count)
            guard nsText.substring(with: closeRange) == marker else { return nil }

            // Find the most recent opening marker that's NOT immediately
            // adjacent (so we don't match the empty `****`).
            let searchUpper = nsText.length - marker.count
            // Walk back looking for marker
            var i = searchUpper - marker.count
            while i >= 0 {
                let r = NSRange(location: i, length: marker.count)
                if nsText.substring(with: r) == marker {
                    // Must have at least one character between the two markers.
                    if i + marker.count <= searchUpper - 1 {
                        // Also avoid matching across a newline — markdown
                        // inline tokens don't span paragraphs.
                        let between = NSRange(location: i + marker.count, length: searchUpper - (i + marker.count))
                        let middle = nsText.substring(with: between)
                        if middle.contains("\n") { return nil }
                        return NSRange(location: i, length: nsText.length - i)
                    }
                    return nil
                }
                i -= 1
            }
            return nil
        }
    }

    private static let patterns: [Pattern] = [
        // ORDER MATTERS — longer markers first so `**` wins over `*`.
        Pattern(marker: "**", restyle: { storage, range, baseFont in
            applyTrait(.bold, in: storage, range: range, baseFont: baseFont)
        }),
        Pattern(marker: "__", restyle: { storage, range, baseFont in
            applyTrait(.bold, in: storage, range: range, baseFont: baseFont)
        }),
        Pattern(marker: "~~", restyle: { storage, range, _ in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }),
        Pattern(marker: "*", restyle: { storage, range, baseFont in
            applyTrait(.italic, in: storage, range: range, baseFont: baseFont)
        }),
        Pattern(marker: "_", restyle: { storage, range, baseFont in
            applyTrait(.italic, in: storage, range: range, baseFont: baseFont)
        }),
        Pattern(marker: "`", restyle: { storage, range, baseFont in
            let mono = PlatformFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
            storage.addAttribute(.font, value: mono, range: range)
        }),
    ]

    private static func apply(pattern: Pattern, match: NSRange,
                              storage: NSMutableAttributedString, baseFont: PlatformFont) -> Result {
        let markerLen = pattern.marker.count
        let innerRange = NSRange(
            location: match.location + markerLen,
            length: match.length - 2 * markerLen
        )
        guard innerRange.length > 0 else { return .noChange }

        // Extract the inner attributed substring (preserves any prior styling).
        let inner = storage.attributedSubstring(from: innerRange).mutableCopy() as! NSMutableAttributedString

        // Apply the pattern's restyle on top of whatever's there.
        let fullInner = NSRange(location: 0, length: inner.length)
        pattern.restyle(inner, fullInner, baseFont)

        storage.beginEditing()
        storage.replaceCharacters(in: match, with: inner)
        storage.endEditing()

        let newCaret = match.location + inner.length
        return Result(replaced: true, newCaret: newCaret)
    }

    // MARK: - Trait helpers (platform-bridged)

    private enum Trait { case bold, italic }

    private static func applyTrait(_ trait: Trait,
                                   in storage: NSMutableAttributedString,
                                   range: NSRange,
                                   baseFont: PlatformFont) {
        storage.enumerateAttribute(.font, in: range) { value, sub, _ in
            let current = (value as? PlatformFont) ?? baseFont
            let newFont = withTrait(trait, on: current)
            storage.addAttribute(.font, value: newFont, range: sub)
        }
    }

    #if canImport(AppKit)
    private static func withTrait(_ trait: Trait, on font: PlatformFont) -> PlatformFont {
        let fm = NSFontManager.shared
        switch trait {
        case .bold:   return fm.convert(font, toHaveTrait: .boldFontMask)
        case .italic: return fm.convert(font, toHaveTrait: .italicFontMask)
        }
    }
    #else
    private static func withTrait(_ trait: Trait, on font: PlatformFont) -> PlatformFont {
        var traits = font.fontDescriptor.symbolicTraits
        switch trait {
        case .bold:   traits.insert(.traitBold)
        case .italic: traits.insert(.traitItalic)
        }
        if let desc = font.fontDescriptor.withSymbolicTraits(traits) {
            return PlatformFont(descriptor: desc, size: font.pointSize)
        }
        return font
    }
    #endif
}
