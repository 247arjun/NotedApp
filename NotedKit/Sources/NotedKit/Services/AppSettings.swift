import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - LaunchBehavior

public enum LaunchBehavior: Int, CaseIterable, Sendable {
    case allNotesAndRestore = 0
    case allNotesOnly       = 1
    case restoreOnly        = 2

    public var displayName: String {
        switch self {
        case .allNotesAndRestore: return "All Notes + Restore Windows"
        case .allNotesOnly:       return "All Notes Only"
        case .restoreOnly:        return "Restore Windows Only"
        }
    }
}

// MARK: - AppSettings

/// Centralized app settings backed by `UserDefaults`. Cross-platform: macOS-
/// only concepts (security-scoped bookmarks, launch behavior, NSFont) are
/// wrapped in conditional compilation.
@MainActor
public final class AppSettings {

    public static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Key {
        static let saveLocationBookmark = "saveLocationBookmark"
        static let saveLocationPath     = "saveLocationPath"
        static let defaultThemeID       = "defaultThemeID"
        static let launchBehavior       = "launchBehavior"
        static let defaultFontName      = "defaultFontName"
        static let defaultFontSize      = "defaultFontSize"
        static let syncWithICloud       = "syncWithICloud"
    }

    private init() {}

    // MARK: - iCloud Sync Toggle

    /// When true, notes live in the iCloud Drive ubiquity container and the
    /// custom save location is ignored. Defaults to **true** if the user is
    /// signed into iCloud on first launch, false otherwise.
    public var syncWithICloud: Bool {
        get {
            if defaults.object(forKey: Key.syncWithICloud) != nil {
                return defaults.bool(forKey: Key.syncWithICloud)
            }
            // First-launch default: prefer iCloud when available.
            return StorageLocationResolver.iCloudAvailable
        }
        set { defaults.set(newValue, forKey: Key.syncWithICloud) }
    }

    // MARK: - Save Location (local)

    #if os(macOS)
    /// User-picked notes directory (security-scoped bookmark). Only meaningful
    /// when `syncWithICloud == false`. Resolved on demand; the bookmark is
    /// refreshed automatically if it goes stale.
    public var customSaveLocationURL: URL? {
        get {
            guard let bookmark = defaults.data(forKey: Key.saveLocationBookmark) else { return nil }
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { return nil }
            if isStale,
               let fresh = try? url.bookmarkData(options: [.withSecurityScope]) {
                defaults.set(fresh, forKey: Key.saveLocationBookmark)
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
    #else
    public var customSaveLocationURL: URL? { nil }
    #endif

    /// Display path for the current effective save location.
    public var saveLocationDisplayPath: String {
        if syncWithICloud {
            return "iCloud Drive › Noted"
        }
        #if os(macOS)
        if let path = defaults.string(forKey: Key.saveLocationPath) {
            return (path as NSString).abbreviatingWithTildeInPath
        }
        #endif
        return defaultSaveDirectory.path
    }

    /// Where notes should actually be stored right now. Falls back to local
    /// default if iCloud is requested but unavailable.
    public var effectiveSaveDirectory: URL {
        if syncWithICloud, let url = StorageLocationResolver.iCloudDirectory() {
            return url
        }
        #if os(macOS)
        if !syncWithICloud, let custom = customSaveLocationURL {
            return custom
        }
        #endif
        return defaultSaveDirectory
    }

    /// Current location as a typed enum (handy for the UI and the resolver).
    public var currentLocation: StorageLocation {
        if syncWithICloud { return .iCloud }
        #if os(macOS)
        if let custom = customSaveLocationURL { return .localCustom(custom) }
        #endif
        return .localDefault
    }

    public var defaultSaveDirectory: URL {
        StorageLocationResolver.defaultLocalDirectory()
    }

    // MARK: - Default Theme

    public var defaultThemeID: String {
        get { defaults.string(forKey: Key.defaultThemeID) ?? ThemeRegistry.defaultThemeID }
        set { defaults.set(newValue, forKey: Key.defaultThemeID) }
    }

    // MARK: - Launch Behavior (macOS only, harmless on iOS)

    public var launchBehavior: LaunchBehavior {
        get { LaunchBehavior(rawValue: defaults.integer(forKey: Key.launchBehavior)) ?? .allNotesAndRestore }
        set { defaults.set(newValue.rawValue, forKey: Key.launchBehavior) }
    }

    // MARK: - Default Font

    public var defaultFontName: String {
        get {
            defaults.string(forKey: Key.defaultFontName)
                ?? PlatformFont.systemFont(ofSize: 15).fontName
        }
        set { defaults.set(newValue, forKey: Key.defaultFontName) }
    }

    public var defaultFontSize: CGFloat {
        get {
            let val = defaults.double(forKey: Key.defaultFontSize)
            return val > 0 ? val : 15.0
        }
        set { defaults.set(Double(newValue), forKey: Key.defaultFontSize) }
    }

    public var defaultFont: PlatformFont {
        PlatformFont(name: defaultFontName, size: defaultFontSize)
            ?? PlatformFont.systemFont(ofSize: defaultFontSize)
    }
}
