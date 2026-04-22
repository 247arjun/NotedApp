import AppKit

// MARK: - LaunchBehavior

enum LaunchBehavior: Int, CaseIterable {
    case allNotesAndRestore = 0   // Show All Notes + restore open note windows
    case allNotesOnly = 1         // Show All Notes only
    case restoreOnly = 2          // Restore open note windows only

    var displayName: String {
        switch self {
        case .allNotesAndRestore: return "All Notes + Restore Windows"
        case .allNotesOnly:       return "All Notes Only"
        case .restoreOnly:        return "Restore Windows Only"
        }
    }
}

// MARK: - AppSettings

/// Centralized app settings backed by UserDefaults.
@MainActor
final class AppSettings {

    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Key {
        static let saveLocationBookmark = "saveLocationBookmark"
        static let saveLocationPath     = "saveLocationPath"
        static let defaultThemeID       = "defaultThemeID"
        static let launchBehavior       = "launchBehavior"
        static let defaultFontName      = "defaultFontName"
        static let defaultFontSize      = "defaultFontSize"
    }

    private init() {}

    // MARK: - Save Location

    /// The custom notes directory, or nil to use the default
    /// `~/Library/Application Support/Noted/Notes/`.
    var customSaveLocationURL: URL? {
        get {
            guard let bookmark = defaults.data(forKey: Key.saveLocationBookmark) else { return nil }
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { return nil }
            if isStale {
                // Re-save bookmark
                if let fresh = try? url.bookmarkData(options: [.withSecurityScope]) {
                    defaults.set(fresh, forKey: Key.saveLocationBookmark)
                }
            }
            return url
        }
        set {
            if let url = newValue {
                let bookmark = try? url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                defaults.set(bookmark, forKey: Key.saveLocationBookmark)
                defaults.set(url.path, forKey: Key.saveLocationPath)
            } else {
                defaults.removeObject(forKey: Key.saveLocationBookmark)
                defaults.removeObject(forKey: Key.saveLocationPath)
            }
        }
    }

    /// Display path for the current save location.
    var saveLocationDisplayPath: String {
        if let path = defaults.string(forKey: Key.saveLocationPath) {
            return (path as NSString).abbreviatingWithTildeInPath
        }
        return defaultSaveDirectory.path
    }

    /// The effective notes directory (custom or default).
    var effectiveSaveDirectory: URL {
        if let custom = customSaveLocationURL {
            return custom
        }
        return defaultSaveDirectory
    }

    /// The built-in default save location.
    var defaultSaveDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("Noted/Notes", isDirectory: true)
    }

    // MARK: - Default Theme

    var defaultThemeID: String {
        get { defaults.string(forKey: Key.defaultThemeID) ?? "yellow" }
        set { defaults.set(newValue, forKey: Key.defaultThemeID) }
    }

    // MARK: - Launch Behavior

    var launchBehavior: LaunchBehavior {
        get { LaunchBehavior(rawValue: defaults.integer(forKey: Key.launchBehavior)) ?? .allNotesAndRestore }
        set { defaults.set(newValue.rawValue, forKey: Key.launchBehavior) }
    }

    // MARK: - Default Font

    var defaultFontName: String {
        get { defaults.string(forKey: Key.defaultFontName) ?? NSFont.systemFont(ofSize: 15).fontName }
        set { defaults.set(newValue, forKey: Key.defaultFontName) }
    }

    var defaultFontSize: CGFloat {
        get {
            let val = defaults.double(forKey: Key.defaultFontSize)
            return val > 0 ? val : 15.0
        }
        set { defaults.set(Double(newValue), forKey: Key.defaultFontSize) }
    }

    var defaultFont: NSFont {
        NSFont(name: defaultFontName, size: defaultFontSize)
            ?? NSFont.systemFont(ofSize: defaultFontSize)
    }
}
