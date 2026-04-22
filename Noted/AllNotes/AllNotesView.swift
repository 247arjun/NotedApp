import SwiftUI

// MARK: - AllNotesView

/// SwiftUI list of all notes with search, reopen, and create.
struct AllNotesView: View {
    @ObservedObject var noteStore: NoteStore
    let onOpenNote: (UUID) -> Void
    let onCreateNote: () -> Void
    let isWindowOpen: (UUID) -> Bool

    @State private var searchText = ""

    private var filteredNotes: [NoteRecord] {
        let all = noteStore.notes.values
            .filter { !$0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
        if searchText.isEmpty { return Array(all) }
        return all.filter { note in
            note.title.localizedCaseInsensitiveContains(searchText)
            || note.bodyExcerpt.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("All Notes")
                    .font(.headline)
                Spacer()
                Button {
                    onCreateNote()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New Note")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search notes…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(8)
            .background(.quaternary)
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()

            // Note list
            if filteredNotes.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "note.text")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "No notes yet" : "No matching notes")
                        .foregroundColor(.secondary)
                    if searchText.isEmpty {
                        Button("Create Note") {
                            onCreateNote()
                        }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(filteredNotes) { note in
                    NoteRowView(
                        note: note,
                        isOpen: isWindowOpen(note.id)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        onOpenNote(note.id)
                    }
                    .onTapGesture(count: 1) {
                        onOpenNote(note.id)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 340, idealWidth: 400, minHeight: 300, idealHeight: 500)
    }
}

// MARK: - NoteRowView

struct NoteRowView: View {
    let note: NoteRecord
    let isOpen: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Theme indicator
            Circle()
                .fill(Color(nsColor: ThemeRegistry.theme(for: note.themeID).headerBackgroundColor))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(note.title.isEmpty ? .secondary : .primary)
                        .lineLimit(1)

                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }

                if !note.bodyExcerpt.isEmpty {
                    Text(note.bodyExcerpt)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Text(note.updatedAt, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if !isOpen {
                Image(systemName: "eye.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .help("Window closed")
            }
        }
        .padding(.vertical, 4)
    }
}
