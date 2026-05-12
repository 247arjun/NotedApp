import SwiftUI
import NotedKit

// MARK: - BucketListView

/// Read-only-ish browser for the Archived and Trash buckets.
///
/// These notes are NOT loaded on app launch — opening this view triggers
/// the on-demand load (`loadArchived()` / `loadTrashed()`) so the active
/// list stays snappy.
struct BucketListView: View {
    let bucket: StorageBucket
    @EnvironmentObject private var noteStore: NoteStore
    @State private var showEmptyTrashConfirm = false
    @State private var deleteForeverID: UUID?

    private var notes: [NoteRecord] {
        let source: [UUID: NoteRecord] = bucket == .archived ? noteStore.archivedNotes : noteStore.trashedNotes
        return source.values.sorted { lhs, rhs in
            let l = (bucket == .trash) ? (lhs.trashedAt ?? lhs.updatedAt) : lhs.updatedAt
            let r = (bucket == .trash) ? (rhs.trashedAt ?? rhs.updatedAt) : rhs.updatedAt
            return l > r
        }
    }

    var body: some View {
        List {
            if notes.isEmpty {
                ContentUnavailableView(
                    bucket == .archived ? "No archived notes" : "Trash is empty",
                    systemImage: bucket == .archived ? "archivebox" : "trash",
                    description: Text(bucket == .archived
                                      ? "Notes you archive will live here, separate from your active list."
                                      : "Deleted notes are kept for 30 days before being permanently removed.")
                )
            } else {
                ForEach(notes) { note in
                    row(for: note)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(bucket == .archived ? "Archived" : "Trash")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if bucket == .trash && !notes.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showEmptyTrashConfirm = true
                    } label: {
                        Text("Empty")
                    }
                }
            }
        }
        .onAppear {
            switch bucket {
            case .archived: noteStore.loadArchived()
            case .trash:    noteStore.loadTrashed()
            case .active:   break
            }
        }
        .confirmationDialog("Empty Trash?", isPresented: $showEmptyTrashConfirm, titleVisibility: .visible) {
            Button("Empty Trash", role: .destructive) {
                noteStore.emptyTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(notes.count) note\(notes.count == 1 ? "" : "s") will be permanently deleted.")
        }
        .confirmationDialog(
            "Delete Forever?",
            isPresented: Binding(
                get: { deleteForeverID != nil },
                set: { if !$0 { deleteForeverID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Forever", role: .destructive) {
                if let id = deleteForeverID { noteStore.deleteForever(noteID: id) }
                deleteForeverID = nil
            }
            Button("Cancel", role: .cancel) { deleteForeverID = nil }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    @ViewBuilder
    private func row(for note: NoteRecord) -> some View {
        BucketNoteRow(note: note, bucket: bucket)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if bucket == .trash {
                    Button(role: .destructive) {
                        deleteForeverID = note.id
                    } label: {
                        Label("Delete Forever", systemImage: "trash.slash")
                    }
                }
                Button {
                    restore(note)
                } label: {
                    Label(bucket == .archived ? "Restore" : "Restore", systemImage: "arrow.uturn.backward")
                }
                .tint(.green)
            }
            .contextMenu {
                Button {
                    restore(note)
                } label: {
                    Label(bucket == .archived ? "Restore to Notes" : "Restore", systemImage: "arrow.uturn.backward")
                }
                if bucket == .archived {
                    Button(role: .destructive) {
                        noteStore.trash(noteID: note.id)
                    } label: {
                        Label("Move to Trash", systemImage: "trash")
                    }
                } else {
                    Button(role: .destructive) {
                        deleteForeverID = note.id
                    } label: {
                        Label("Delete Forever", systemImage: "trash.slash")
                    }
                }
            }
    }

    private func restore(_ note: NoteRecord) {
        switch bucket {
        case .archived: noteStore.unarchive(noteID: note.id)
        case .trash:    noteStore.restoreFromTrash(noteID: note.id)
        case .active:   break
        }
    }
}

// MARK: - Row

private struct BucketNoteRow: View {
    let note: NoteRecord
    let bucket: StorageBucket

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title.isEmpty ? "Untitled" : note.title)
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(note.title.isEmpty ? .secondary : .primary)
            if !note.bodyExcerpt.isEmpty {
                Text(note.bodyExcerpt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(metaLine)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var metaLine: String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        if bucket == .trash, let t = note.trashedAt {
            let daysLeft = max(0, 30 - Int(Date().timeIntervalSince(t) / 86_400))
            return "Trashed \(df.string(from: t)) • \(daysLeft) day\(daysLeft == 1 ? "" : "s") left"
        }
        return df.string(from: note.updatedAt)
    }
}
