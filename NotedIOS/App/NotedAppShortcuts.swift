import AppIntents
import NotedKit

// MARK: - NotedAppShortcuts (iOS)

/// Exposes the NotedKit app intents to Siri, Spotlight, and the Shortcuts
/// app on iOS / iPadOS. Phrases include the app name (Apple requires it).
struct NotedAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateNoteIntent(),
            phrases: [
                "New note in \(.applicationName)",
                "Create a note in \(.applicationName)",
                "Start a \(.applicationName) note",
            ],
            shortTitle: "New Note",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: SearchNotesIntent(),
            phrases: [
                "Search \(.applicationName) for \(\.$query)",
                "Find notes about \(\.$query) in \(.applicationName)",
            ],
            shortTitle: "Search Notes",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenNoteIntent(),
            phrases: [
                "Open note in \(.applicationName)",
                "Open \(\.$note) in \(.applicationName)",
            ],
            shortTitle: "Open Note",
            systemImageName: "note.text"
        )
    }
}
