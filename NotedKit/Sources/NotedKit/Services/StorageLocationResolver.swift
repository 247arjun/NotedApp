import Foundation

// MARK: - StorageLocation

/// Where notes are persisted.
public enum StorageLocation: Equatable, Sendable {
    /// `~/Library/Application Support/<bundle>/Notes/` — sandboxed app container.
    case localDefault
    /// A user-picked folder accessed via a security-scoped bookmark (macOS only).
    case localCustom(URL)
    /// iCloud Drive ubiquity container `Documents/` folder, surfaced as "Noted"
    /// in the user's iCloud Drive thanks to `NSUbiquitousContainers` in Info.plist.
    case iCloud
}

// MARK: - StorageLocationResolver

/// Resolves a `StorageLocation` to a concrete on-disk `URL`. Centralised so the
/// iCloud-container lookup logic lives in exactly one place across both apps.
public enum StorageLocationResolver {

    /// iCloud container identifier shared by both macOS and iOS targets.
    public static let iCloudContainerID = "iCloud.com.arjun.Noted"

    /// Resolves a location to a usable directory URL. Returns nil only for
    /// `.iCloud` when the user is not signed into iCloud / iCloud Drive is off.
    public static func resolve(_ location: StorageLocation) -> URL? {
        switch location {
        case .localDefault:
            return defaultLocalDirectory()
        case .localCustom(let url):
            return url
        case .iCloud:
            return iCloudDirectory()
        }
    }

    /// The built-in local fallback. Inside the sandbox this resolves to the
    /// app's container Application Support directory.
    public static func defaultLocalDirectory() -> URL {
        if let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first {
            return appSupport.appendingPathComponent("Noted/Notes", isDirectory: true)
        }
        // Last-resort fallback. Application Support should always exist on
        // both platforms, so this branch is effectively unreachable.
        let tmp = FileManager.default.temporaryDirectory
        return tmp.appendingPathComponent("Noted/Notes", isDirectory: true)
    }

    /// iCloud Drive Documents folder for the Noted ubiquity container. Returns
    /// nil if the user is not signed into iCloud or the container isn't ready
    /// yet (caller should fall back to local storage in that case).
    public static func iCloudDirectory() -> URL? {
        guard let containerURL = FileManager.default
            .url(forUbiquityContainerIdentifier: iCloudContainerID) else { return nil }
        let docs = containerURL.appendingPathComponent("Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        return docs
    }

    /// True when iCloud Drive is available for this user. Useful for greying
    /// out the "Sync with iCloud" toggle in Settings when it can't work.
    public static var iCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
}
