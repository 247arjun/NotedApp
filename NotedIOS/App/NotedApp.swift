import SwiftUI
import NotedKit

@main
struct NotedApp: App {

    @StateObject private var appModel = AppModel.shared

    var body: some Scene {
        // Main list scene
        WindowGroup("Noted", id: "main") {
            RootView()
                .environmentObject(appModel)
                .environmentObject(appModel.noteStore)
        }

        // Per-note scenes — on iPadOS the user can open each note in its own
        // window (Stage Manager / Split View). On iPhone these collapse into
        // ordinary push navigation from the list.
        WindowGroup("Note", id: "note", for: UUID.self) { $noteID in
            if let id = noteID {
                NoteEditorScene(noteID: id)
                    .environmentObject(appModel)
                    .environmentObject(appModel.noteStore)
            } else {
                Text("No note selected").foregroundStyle(.secondary)
            }
        }
    }
}
