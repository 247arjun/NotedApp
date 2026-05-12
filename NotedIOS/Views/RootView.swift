import SwiftUI
import NotedKit

// MARK: - RootView

/// On iPhone: NavigationStack with the note list, drilling into the editor.
/// On iPad: NavigationSplitView with the list as sidebar and editor as detail.
struct RootView: View {
    @EnvironmentObject private var noteStore: NoteStore
    @State private var selectedNoteID: UUID?
    @State private var showSettings = false
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        Group {
            if hSizeClass == .regular {
                NavigationSplitView {
                    NoteListView(selection: $selectedNoteID, showSettings: $showSettings)
                } detail: {
                    if let id = selectedNoteID, noteStore.notes[id] != nil {
                        NoteEditorView(noteID: id)
                            .id(id)
                    } else {
                        ContentUnavailableView(
                            "Select a note",
                            systemImage: "note.text",
                            description: Text("Pick a note from the sidebar or create a new one.")
                        )
                    }
                }
            } else {
                NavigationStack {
                    NoteListView(selection: $selectedNoteID, showSettings: $showSettings)
                        .navigationDestination(item: $selectedNoteID) { id in
                            NoteEditorView(noteID: id)
                        }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
    }
}

// MARK: - NoteEditorScene

/// Standalone scene host opened via `openWindow(id: "note", value: noteID)`
/// on iPadOS for the "open in own window" experience.
struct NoteEditorScene: View {
    let noteID: UUID
    @EnvironmentObject private var noteStore: NoteStore

    var body: some View {
        NavigationStack {
            if noteStore.notes[noteID] != nil {
                NoteEditorView(noteID: noteID)
            } else {
                ContentUnavailableView("Note not found", systemImage: "questionmark.folder")
            }
        }
    }
}
