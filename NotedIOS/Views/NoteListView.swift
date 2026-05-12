import SwiftUI
import NotedKit

// MARK: - NoteListView

struct NoteListView: View {
    @EnvironmentObject private var noteStore: NoteStore
    @EnvironmentObject private var appModel: AppModel
    @Binding var selection: UUID?
    @Binding var showSettings: Bool

    @State private var searchText: String = ""
    @State private var sortMode: SortMode = .updated
    @Environment(\.openWindow) private var openWindow

    enum SortMode: String, CaseIterable, Identifiable {
        case updated = "Date Modified"
        case created = "Date Created"
        case titleAZ = "Title (A→Z)"
        case titleZA = "Title (Z→A)"

        var id: String { rawValue }
    }

    private var pinned: [NoteRecord]  { sortedAndFiltered.filter { $0.isPinned } }
    private var others: [NoteRecord]  { sortedAndFiltered.filter { !$0.isPinned } }

    private var sortedAndFiltered: [NoteRecord] {
        var all = Array(noteStore.notes.values.filter { !$0.isArchived })
        if !searchText.isEmpty {
            all = all.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.bodyPlainText.localizedCaseInsensitiveContains(searchText)
            }
        }
        switch sortMode {
        case .updated: return all.sorted { $0.updatedAt > $1.updatedAt }
        case .created: return all.sorted { $0.createdAt > $1.createdAt }
        case .titleAZ: return all.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .titleZA: return all.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        }
    }

    var body: some View {
        List(selection: $selection) {
            if !pinned.isEmpty {
                Section("Pinned") { ForEach(pinned) { row(for: $0) } }
            }
            Section(pinned.isEmpty ? "Notes" : "Others") {
                if others.isEmpty && pinned.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No notes yet" : "No matching notes",
                        systemImage: "note.text",
                        description: Text(searchText.isEmpty ? "Tap + to create your first note." : "Try a different search.")
                    )
                } else {
                    ForEach(others) { row(for: $0) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Noted")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search notes")
        .refreshable { appModel.refresh() }
        .toolbar { toolbarContent }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                NavigationLink {
                    BucketListView(bucket: .archived)
                } label: {
                    Label("Archived", systemImage: "archivebox")
                }
                NavigationLink {
                    BucketListView(bucket: .trash)
                } label: {
                    Label("Trash", systemImage: "trash")
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
            .accessibilityLabel("Menu")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort by", selection: $sortMode) {
                    ForEach(SortMode.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                let note = noteStore.createNote()
                selection = note.id
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .accessibilityLabel("New note")
        }
    }

    @ViewBuilder
    private func row(for note: NoteRecord) -> some View {
        NoteRow(note: note)
            .tag(note.id)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    if selection == note.id { selection = nil }
                    noteStore.deleteNote(noteID: note.id)  // → Trash (30-day grace)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    if selection == note.id { selection = nil }
                    noteStore.archive(noteID: note.id)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .tint(.gray)
            }
            .swipeActions(edge: .leading) {
                Button {
                    noteStore.updatePinned(noteID: note.id, isPinned: !note.isPinned)
                } label: {
                    Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
                }
                .tint(.orange)
            }
            .contextMenu {
                Button {
                    noteStore.updatePinned(noteID: note.id, isPinned: !note.isPinned)
                } label: {
                    Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
                }
                Button {
                    if let dup = noteStore.duplicateNote(noteID: note.id) {
                        selection = dup.id
                    }
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                Button {
                    if selection == note.id { selection = nil }
                    noteStore.archive(noteID: note.id)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                #if os(iOS)
                if UIDevice.current.userInterfaceIdiom == .pad {
                    Button {
                        openWindow(id: "note", value: note.id)
                    } label: {
                        Label("Open in New Window", systemImage: "macwindow.badge.plus")
                    }
                }
                #endif
                Divider()
                Button(role: .destructive) {
                    if selection == note.id { selection = nil }
                    noteStore.deleteNote(noteID: note.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
}

// MARK: - NoteRow

private struct NoteRow: View {
    let note: NoteRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(themeColor))
                .frame(width: 6)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(note.title.isEmpty ? .secondary : .primary)
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                if !note.bodyExcerpt.isEmpty {
                    Text(note.bodyExcerpt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(note.updatedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var themeColor: PlatformColor {
        ThemeRegistry.theme(for: note.themeID).headerBackgroundColor
    }
}
