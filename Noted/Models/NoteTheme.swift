import AppKit

// MARK: - NoteTheme

struct NoteTheme: Equatable, Identifiable {
    let id: String
    let displayName: String
    let bodyBackgroundColor: NSColor
    let headerBackgroundColor: NSColor
    let titleTextColor: NSColor
    let bodyTextColor: NSColor
    let placeholderTextColor: NSColor
    let controlTintColor: NSColor
    let foldedCornerColor: NSColor
}

// MARK: - ThemeRegistry

enum ThemeRegistry {

    static let defaultThemeID = "yellow"

    static let allThemes: [NoteTheme] = [yellow, pink, blue, green, white]

    static func theme(for id: String) -> NoteTheme {
        allThemes.first(where: { $0.id == id }) ?? yellow
    }

    // MARK: Built-in themes

    static let yellow = NoteTheme(
        id: "yellow",
        displayName: "Yellow",
        bodyBackgroundColor:       NSColor(red: 1.00, green: 0.99, blue: 0.88, alpha: 1),
        headerBackgroundColor:     NSColor(red: 1.00, green: 0.94, blue: 0.55, alpha: 1),
        titleTextColor:            NSColor(red: 0.26, green: 0.23, blue: 0.05, alpha: 1),
        bodyTextColor:             NSColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1),
        placeholderTextColor:      NSColor(red: 0.55, green: 0.50, blue: 0.28, alpha: 1),
        controlTintColor:          NSColor(red: 0.40, green: 0.36, blue: 0.10, alpha: 1),
        foldedCornerColor:         NSColor(red: 0.90, green: 0.84, blue: 0.38, alpha: 1)
    )

    static let pink = NoteTheme(
        id: "pink",
        displayName: "Pink",
        bodyBackgroundColor:       NSColor(red: 1.00, green: 0.91, blue: 0.93, alpha: 1),
        headerBackgroundColor:     NSColor(red: 0.96, green: 0.56, blue: 0.69, alpha: 1),
        titleTextColor:            NSColor(red: 0.35, green: 0.08, blue: 0.15, alpha: 1),
        bodyTextColor:             NSColor(red: 0.15, green: 0.12, blue: 0.13, alpha: 1),
        placeholderTextColor:      NSColor(red: 0.60, green: 0.35, blue: 0.42, alpha: 1),
        controlTintColor:          NSColor(red: 0.45, green: 0.12, blue: 0.22, alpha: 1),
        foldedCornerColor:         NSColor(red: 0.90, green: 0.48, blue: 0.58, alpha: 1)
    )

    static let blue = NoteTheme(
        id: "blue",
        displayName: "Blue",
        bodyBackgroundColor:       NSColor(red: 0.89, green: 0.95, blue: 1.00, alpha: 1),
        headerBackgroundColor:     NSColor(red: 0.56, green: 0.79, blue: 0.98, alpha: 1),
        titleTextColor:            NSColor(red: 0.07, green: 0.17, blue: 0.32, alpha: 1),
        bodyTextColor:             NSColor(red: 0.12, green: 0.14, blue: 0.17, alpha: 1),
        placeholderTextColor:      NSColor(red: 0.30, green: 0.45, blue: 0.60, alpha: 1),
        controlTintColor:          NSColor(red: 0.12, green: 0.28, blue: 0.48, alpha: 1),
        foldedCornerColor:         NSColor(red: 0.45, green: 0.68, blue: 0.88, alpha: 1)
    )

    static let green = NoteTheme(
        id: "green",
        displayName: "Green",
        bodyBackgroundColor:       NSColor(red: 0.91, green: 0.96, blue: 0.91, alpha: 1),
        headerBackgroundColor:     NSColor(red: 0.55, green: 0.80, blue: 0.55, alpha: 1),
        titleTextColor:            NSColor(red: 0.10, green: 0.25, blue: 0.10, alpha: 1),
        bodyTextColor:             NSColor(red: 0.12, green: 0.15, blue: 0.12, alpha: 1),
        placeholderTextColor:      NSColor(red: 0.30, green: 0.50, blue: 0.30, alpha: 1),
        controlTintColor:          NSColor(red: 0.15, green: 0.35, blue: 0.15, alpha: 1),
        foldedCornerColor:         NSColor(red: 0.45, green: 0.70, blue: 0.45, alpha: 1)
    )

    static let white = NoteTheme(
        id: "white",
        displayName: "White",
        bodyBackgroundColor:       NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1),
        headerBackgroundColor:     NSColor(red: 0.88, green: 0.88, blue: 0.88, alpha: 1),
        titleTextColor:            NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1),
        bodyTextColor:             NSColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1),
        placeholderTextColor:      NSColor(red: 0.50, green: 0.50, blue: 0.50, alpha: 1),
        controlTintColor:          NSColor(red: 0.30, green: 0.30, blue: 0.30, alpha: 1),
        foldedCornerColor:         NSColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1)
    )
}
