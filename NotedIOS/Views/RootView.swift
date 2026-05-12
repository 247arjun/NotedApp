import SwiftUI
import NotedKit

// MARK: - RootView

/// Hosts the iOS / iPadOS chrome. The "current bucket" (Active / Archived /
/// Trash) is top-level state held here so that switching it via the sidebar's
/// hamburger menu replaces the *sidebar root* — not pushes a deeper view —
/// and the detail pane stays in sync.
struct RootView: View {
    @EnvironmentObject private var noteStore: NoteStore
    @EnvironmentObject private var appModel: AppModel

    @State private var activeBucket: StorageBucket = .active
    @State private var selectedNoteID: UUID?
    @State private var showSettings = false
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        Group {
            if hSizeClass == .regular {
                NavigationSplitView {
                    sidebar
                } detail: {
                    detailPane
                }
            } else {
                NavigationStack {
                    sidebar
                        .navigationDestination(item: $selectedNoteID) { id in
                            editor(for: id)
                        }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
        .onChange(of: activeBucket) { _, _ in
            // Switching buckets clears any selection from the previous bucket.
            selectedNoteID = nil
        }
        .onChange(of: appModel.pendingOpenNoteID) { _, id in
            guard let id else { return }
            // Intent-routed opens always jump back to Active.
            activeBucket = .active
            selectedNoteID = id
            appModel.pendingOpenNoteID = nil
        }
    }

    // MARK: - Sidebar root

    @ViewBuilder
    private var sidebar: some View {
        switch activeBucket {
        case .active:
            NoteListView(
                selection: $selectedNoteID,
                activeBucket: $activeBucket,
                showSettings: $showSettings
            )
        case .archived:
            BucketListView(
                bucket: .archived,
                selection: $selectedNoteID,
                activeBucket: $activeBucket,
                showSettings: $showSettings
            )
        case .trash:
            BucketListView(
                bucket: .trash,
                selection: $selectedNoteID,
                activeBucket: $activeBucket,
                showSettings: $showSettings
            )
        }
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detailPane: some View {
        if let id = selectedNoteID, resolve(id) != nil {
            editor(for: id)
        } else {
            ContentUnavailableView(
                emptyTitle,
                systemImage: emptySymbol,
                description: Text(emptySubtitle)
            )
        }
    }

    @ViewBuilder
    private func editor(for id: UUID) -> some View {
        if let note = resolve(id) {
            NoteEditorView(
                noteID: id,
                isReadOnly: note.isArchived || note.isInTrash,
                bucket: bucketForNote(note),
                onRestoredToActive: {
                    // After restore / unarchive the note is in Active.
                    activeBucket = .active
                    selectedNoteID = id
                }
            )
            .id(id)
        } else {
            ContentUnavailableView("Note not found", systemImage: "questionmark.folder")
        }
    }

    // MARK: - Helpers

    private func resolve(_ id: UUID) -> NoteRecord? {
        noteStore.notes[id]
            ?? noteStore.archivedNotes[id]
            ?? noteStore.trashedNotes[id]
    }

    private func bucketForNote(_ note: NoteRecord) -> StorageBucket {
        if note.isInTrash  { return .trash }
        if note.isArchived { return .archived }
        return .active
    }

    private var emptyTitle: String {
        switch activeBucket {
        case .active:   return "Select a note"
        case .archived: return "Select an archived note"
        case .trash:    return "Select a note in Trash"
        }
    }

    private var emptySymbol: String {
        switch activeBucket {
        case .active:   return "note.text"
        case .archived: return "archivebox"
        case .trash:    return "trash"
        }
    }

    private var emptySubtitle: String {
        switch activeBucket {
        case .active:   return "Pick a note from the sidebar or create a new one."
        case .archived: return "Tap a note to view its contents. Restore to edit again."
        case .trash:    return "Notes here will be deleted automatically after 30 days."
        }
    }
}

// MARK: - NoteEditorScene

/// Standalone scene host for the iPadOS "open in own window" experience.
/// Archived / trashed notes open read-only.
struct NoteEditorScene: View {
    let noteID: UUID
    @EnvironmentObject private var noteStore: NoteStore

    var body: some View {
        NavigationStack {
            if let note = noteStore.notes[noteID]
                ?? noteStore.archivedNotes[noteID]
                ?? noteStore.trashedNotes[noteID] {
                NoteEditorView(
                    noteID: noteID,
                    isReadOnly: note.isArchived || note.isInTrash,
                    bucket: note.isInTrash ? .trash : (note.isArchived ? .archived : .active),
                    onRestoredToActive: nil
                )
            } else {
                ContentUnavailableView("Note not found", systemImage: "questionmark.folder")
            }
        }
    }
}

// MARK: - BucketSwitcherMenu

/// Shared "hamburger" menu used by every sidebar-root view. Lets the user
/// switch between Active / Archived / Trash and reach Settings.
struct BucketSwitcherMenu: View {
    @Binding var activeBucket: StorageBucket
    @Binding var showSettings: Bool

    var body: some View {
        Menu {
            Picker("Folder", selection: $activeBucket) {
                Label("Active Notes", systemImage: "note.text").tag(StorageBucket.active)
                Label("Archived",     systemImage: "archivebox").tag(StorageBucket.archived)
                Label("Trash",        systemImage: "trash").tag(StorageBucket.trash)
            }
            Divider()
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "line.3.horizontal")
        }
        .accessibilityLabel("Folder menu")
    }
}
