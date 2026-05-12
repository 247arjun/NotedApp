import UIKit
import NotedKit

// MARK: - Home Screen quick action plumbing

/// Identifier for the static "New Note" Home Screen shortcut declared in
/// Info.plist. Kept in one place so the plist value, the cold-launch path,
/// and the warm-launch path all stay in sync.
enum HomeScreenShortcut {
    static let newNoteType = "com.arjun.Noted.ios.new-note"
}

// MARK: - AppDelegate

/// Minimal `UIApplicationDelegate` whose sole job is to install a custom
/// scene delegate (`NotedSceneDelegate`) so we can receive
/// `windowScene(_:performActionFor:)` callbacks for Home Screen quick actions.
/// SwiftUI's `WindowGroup` continues to own actual window setup — we only
/// hook the OS callbacks the framework doesn't surface.
final class NotedAppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        config.delegateClass = NotedSceneDelegate.self
        return config
    }
}

// MARK: - SceneDelegate

/// Receives Home Screen quick action events. Implements only the shortcut
/// callbacks — does NOT touch `window` (SwiftUI's internal scene plumbing
/// continues to manage that via `WindowGroup`).
final class NotedSceneDelegate: NSObject, UIWindowSceneDelegate {

    var window: UIWindow?  // intentionally left to SwiftUI

    // Cold launch: the shortcut item is in connectionOptions
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let item = connectionOptions.shortcutItem {
            handle(item)
        }
    }

    // Warm launch: app was already running in the background
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(handle(shortcutItem))
    }

    @discardableResult
    private func handle(_ item: UIApplicationShortcutItem) -> Bool {
        guard item.type == HomeScreenShortcut.newNoteType else { return false }
        Task { @MainActor in
            AppModel.shared.createAndOpenNote()
        }
        return true
    }
}
