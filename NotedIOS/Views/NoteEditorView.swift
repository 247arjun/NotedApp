import SwiftUI
import UIKit
import NotedKit

// MARK: - NoteEditorView

/// Editor surface for a single note. Works for any bucket:
///   - .active   → fully editable; pin / theme / delete / new-window toolbar
///   - .archived → read-only with a banner offering Restore / Move to Trash
///   - .trash    → read-only with a banner offering Restore / Delete Forever
struct NoteEditorView: View {
    let noteID: UUID
    let isReadOnly: Bool
    let bucket: StorageBucket
    /// Called when the note transitions back to Active (Restore / Unarchive).
    /// Lets RootView jump the sidebar back to the Active bucket.
    let onRestoredToActive: (() -> Void)?

    @EnvironmentObject private var noteStore: NoteStore
    @Environment(\.openWindow) private var openWindow

    @State private var title: String = ""
    @State private var bodyData: Data = Data()
    @State private var showingThemePicker = false
    @State private var deleteForeverConfirm = false
    @State private var moveToTrashConfirm = false

    private var note: NoteRecord? {
        noteStore.notes[noteID]
            ?? noteStore.archivedNotes[noteID]
            ?? noteStore.trashedNotes[noteID]
    }
    private var theme: NoteTheme {
        ThemeRegistry.theme(for: note?.themeID ?? ThemeRegistry.defaultThemeID)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isReadOnly { readOnlyBanner }

            TextField("Untitled", text: $title)
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(theme.headerBackgroundColor))
                .foregroundStyle(Color(theme.titleTextColor))
                .disabled(isReadOnly)
                .onChange(of: title) { _, newValue in
                    guard !isReadOnly else { return }
                    noteStore.updateTitle(noteID: noteID, title: newValue)
                }

            RichTextEditor(
                attributedData: $bodyData,
                theme: theme,
                isReadOnly: isReadOnly
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
            guard !isReadOnly else { return }
            noteStore.updateBody(noteID: noteID, attributedData: newData)
        }
        .sheet(isPresented: $showingThemePicker) {
            ThemePickerView(currentThemeID: note?.themeID ?? ThemeRegistry.defaultThemeID) { newID in
                noteStore.updateTheme(noteID: noteID, themeID: newID)
                showingThemePicker = false
            }
            .presentationDetents([.height(200)])
        }
        .confirmationDialog("Delete this note?",
                            isPresented: $deleteForeverConfirm,
                            titleVisibility: .visible) {
            Button("Delete Forever", role: .destructive) {
                noteStore.deleteForever(noteID: noteID)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .confirmationDialog("Move this note to Trash?",
                            isPresented: $moveToTrashConfirm,
                            titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                noteStore.trash(noteID: noteID)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Trashed notes are kept for 30 days before they're permanently deleted.")
        }
    }

    // MARK: - Read-only banner

    @ViewBuilder
    private var readOnlyBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: bucket == .archived ? "archivebox.fill" : "trash.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text(bucket == .archived ? "Archived" : "In Trash")
                    .font(.subheadline.weight(.semibold))
                Text(bucket == .archived
                     ? "Restore to edit this note."
                     : trashSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Restore") { restore() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private var trashSubtitle: String {
        guard bucket == .trash, let t = note?.trashedAt else { return "" }
        let daysLeft = max(0, 30 - Int(Date().timeIntervalSince(t) / 86_400))
        return "Permanently deleted in \(daysLeft) day\(daysLeft == 1 ? "" : "s")."
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isReadOnly {
            // Archived / Trash — Restore + destructive option in a menu.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        restore()
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    if bucket == .trash {
                        Button(role: .destructive) {
                            deleteForeverConfirm = true
                        } label: {
                            Label("Delete Forever", systemImage: "trash.slash")
                        }
                    } else {
                        Button(role: .destructive) {
                            moveToTrashConfirm = true
                        } label: {
                            Label("Move to Trash", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        } else {
            // Active — full editing toolbar
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
                    #if os(iOS)
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        Button {
                            openWindow(id: "note", value: noteID)
                        } label: {
                            Label("Open in New Window", systemImage: "macwindow.badge.plus")
                        }
                    }
                    #endif
                    Button {
                        noteStore.archive(noteID: noteID)
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    Button(role: .destructive) {
                        moveToTrashConfirm = true
                    } label: {
                        Label("Move to Trash", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: - Actions

    private func restore() {
        switch bucket {
        case .archived: noteStore.unarchive(noteID: noteID)
        case .trash:    noteStore.restoreFromTrash(noteID: noteID)
        case .active:   break
        }
        onRestoredToActive?()
    }

    private func loadFromStore() {
        guard let n = note else { return }
        title = n.title
        bodyData = n.attributedBodyData
    }
}
