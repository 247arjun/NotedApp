import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - NoteTheme

public struct NoteTheme: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let bodyBackgroundColor: PlatformColor
    public let headerBackgroundColor: PlatformColor
    public let titleTextColor: PlatformColor
    public let bodyTextColor: PlatformColor
    public let placeholderTextColor: PlatformColor
    public let controlTintColor: PlatformColor
    public let foldedCornerColor: PlatformColor

    public init(
        id: String,
        displayName: String,
        bodyBackgroundColor: PlatformColor,
        headerBackgroundColor: PlatformColor,
        titleTextColor: PlatformColor,
        bodyTextColor: PlatformColor,
        placeholderTextColor: PlatformColor,
        controlTintColor: PlatformColor,
        foldedCornerColor: PlatformColor
    ) {
        self.id = id
        self.displayName = displayName
        self.bodyBackgroundColor = bodyBackgroundColor
        self.headerBackgroundColor = headerBackgroundColor
        self.titleTextColor = titleTextColor
        self.bodyTextColor = bodyTextColor
        self.placeholderTextColor = placeholderTextColor
        self.controlTintColor = controlTintColor
        self.foldedCornerColor = foldedCornerColor
    }
}

// MARK: - ThemeRegistry

public enum ThemeRegistry {

    public static let defaultThemeID = "yellow"

    public static let allThemes: [NoteTheme] = [yellow, pink, blue, green, white]

    public static func theme(for id: String) -> NoteTheme {
        allThemes.first(where: { $0.id == id }) ?? yellow
    }

    // MARK: Built-in themes

    public static let yellow = NoteTheme(
        id: "yellow",
        displayName: "Yellow",
        bodyBackgroundColor:   .rgb(1.00, 0.99, 0.88),
        headerBackgroundColor: .rgb(1.00, 0.94, 0.55),
        titleTextColor:        .rgb(0.26, 0.23, 0.05),
        bodyTextColor:         .rgb(0.13, 0.13, 0.13),
        placeholderTextColor:  .rgb(0.55, 0.50, 0.28),
        controlTintColor:      .rgb(0.40, 0.36, 0.10),
        foldedCornerColor:     .rgb(0.90, 0.84, 0.38)
    )

    public static let pink = NoteTheme(
        id: "pink",
        displayName: "Pink",
        bodyBackgroundColor:   .rgb(1.00, 0.91, 0.93),
        headerBackgroundColor: .rgb(0.96, 0.56, 0.69),
        titleTextColor:        .rgb(0.35, 0.08, 0.15),
        bodyTextColor:         .rgb(0.15, 0.12, 0.13),
        placeholderTextColor:  .rgb(0.60, 0.35, 0.42),
        controlTintColor:      .rgb(0.45, 0.12, 0.22),
        foldedCornerColor:     .rgb(0.90, 0.48, 0.58)
    )

    public static let blue = NoteTheme(
        id: "blue",
        displayName: "Blue",
        bodyBackgroundColor:   .rgb(0.89, 0.95, 1.00),
        headerBackgroundColor: .rgb(0.56, 0.79, 0.98),
        titleTextColor:        .rgb(0.07, 0.17, 0.32),
        bodyTextColor:         .rgb(0.12, 0.14, 0.17),
        placeholderTextColor:  .rgb(0.30, 0.45, 0.60),
        controlTintColor:      .rgb(0.12, 0.28, 0.48),
        foldedCornerColor:     .rgb(0.45, 0.68, 0.88)
    )

    public static let green = NoteTheme(
        id: "green",
        displayName: "Green",
        bodyBackgroundColor:   .rgb(0.91, 0.96, 0.91),
        headerBackgroundColor: .rgb(0.55, 0.80, 0.55),
        titleTextColor:        .rgb(0.10, 0.25, 0.10),
        bodyTextColor:         .rgb(0.12, 0.15, 0.12),
        placeholderTextColor:  .rgb(0.30, 0.50, 0.30),
        controlTintColor:      .rgb(0.15, 0.35, 0.15),
        foldedCornerColor:     .rgb(0.45, 0.70, 0.45)
    )

    public static let white = NoteTheme(
        id: "white",
        displayName: "White",
        bodyBackgroundColor:   .rgb(0.98, 0.98, 0.98),
        headerBackgroundColor: .rgb(0.88, 0.88, 0.88),
        titleTextColor:        .rgb(0.15, 0.15, 0.15),
        bodyTextColor:         .rgb(0.13, 0.13, 0.13),
        placeholderTextColor:  .rgb(0.50, 0.50, 0.50),
        controlTintColor:      .rgb(0.30, 0.30, 0.30),
        foldedCornerColor:     .rgb(0.75, 0.75, 0.75)
    )
}
