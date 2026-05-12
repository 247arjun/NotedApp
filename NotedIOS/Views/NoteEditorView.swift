import SwiftUI
import UIKit
import NotedKit

// MARK: - NoteEditorView

struct NoteEditorView: View {
    let noteID: UUID
    @EnvironmentObject private var noteStore: NoteStore
    @Environment(\.openWindow) private var openWindow

    @State private var title: String = ""
    @State private var bodyData: Data = Data()
    @State private var showingThemePicker = false
    @State private var deleteConfirm = false

    private var note: NoteRecord? { noteStore.notes[noteID] }
    private var theme: NoteTheme { ThemeRegistry.theme(for: note?.themeID ?? ThemeRegistry.defaultThemeID) }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Untitled", text: $title)
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(theme.headerBackgroundColor))
                .foregroundStyle(Color(theme.titleTextColor))
                .onChange(of: title) { _, newValue in
                    noteStore.updateTitle(noteID: noteID, title: newValue)
                }

            RichTextEditor(
                attributedData: $bodyData,
                theme: theme
            )
            .background(Color(theme.bodyBackgroundColor))
        }
        .background(Color(theme.bodyBackgroundColor).ignoresSafeArea())
        .navigationTitle(title.isEmpty ? "Untitled" : title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear { loadFromStore() }
        .onChange(of: noteID) { _, _ in loadFromStore() }
        .onChange(of: bodyData) { _, newData in
            // Only push if local change (the editor pushes through state)
            noteStore.updateBody(noteID: noteID, attributedData: newData)
        }
        .sheet(isPresented: $showingThemePicker) {
            ThemePickerView(currentThemeID: note?.themeID ?? ThemeRegistry.defaultThemeID) { newID in
                noteStore.updateTheme(noteID: noteID, themeID: newID)
                showingThemePicker = false
            }
            .presentationDetents([.height(200)])
        }
        .confirmationDialog("Delete this note?", isPresented: $deleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                noteStore.deleteNote(noteID: noteID)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                guard let n = note else { return }
                noteStore.updatePinned(noteID: noteID, isPinned: !n.isPinned)
            } label: {
                Image(systemName: (note?.isPinned ?? false) ? "pin.fill" : "pin")
            }
            .accessibilityLabel((note?.isPinned ?? false) ? "Unpin" : "Pin")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingThemePicker = true
            } label: {
                Image(systemName: "paintpalette")
            }
            .accessibilityLabel("Change color")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    Button {
                        openWindow(id: "note", value: noteID)
                    } label: {
                        Label("Open in New Window", systemImage: "macwindow.badge.plus")
                    }
                }
                Button(role: .destructive) {
                    deleteConfirm = true
                } label: {
                    Label("Delete Note", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private func loadFromStore() {
        guard let n = note else { return }
        title = n.title
        bodyData = n.attributedBodyData
    }
}
