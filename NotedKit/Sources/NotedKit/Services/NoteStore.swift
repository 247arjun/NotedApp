import Foundation
import Combine

// MARK: - NoteStore

/// Single source of truth for note data.
///
/// **Bucket model:**
/// - `notes` — the active set, loaded on launch. Fast. This is what the
///   main list views observe.
/// - `archivedNotes` and `trashedNotes` — loaded on demand by the
///   Archived / Trash views via `loadArchived()` / `loadTrashed()`.
///   They aren't part of the launch path.
///
/// Moving a note between buckets physically relocates its files in the
/// iCloud Drive notes folder (Active / Archived/ / Trash/ subfolders).
@MainActor
public final class NoteStore: ObservableObject {

    // MARK: - Published state

    /// Active notes only. Mutating this never includes archived or trashed
    /// notes — those have their own published collections below.
    @Published public private(set) var notes: [UUID: NoteRecord] = [:]

    /// Archived notes — empty until `loadArchived()` is called.
    @Published public private(set) var archivedNotes: [UUID: NoteRecord] = [:]

    /// Trashed notes — empty until `loadTrashed()` is called.
    @Published public private(set) var trashedNotes: [UUID: NoteRecord] = [:]

    // MARK: - Dependencies

    public private(set) var persistenceService: PersistenceService

    // MARK: - Debounce

    private let bodySaveSubject  = PassthroughSubject<UUID, Never>()
    private let frameSaveSubject = PassthroughSubject<UUID, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var pendingNoteIDs = Set<UUID>()

    // MARK: - iCloud observer

    private var changeObserver: iCloudChangeObserver?
    private var changeObserverCancellable: AnyCancellable?

    public init(persistenceService: PersistenceService) {
        self.persistenceService = persistenceService
        setupDebounce()
    }

    // MARK: - Backend swap

    public func swapPersistenceService(_ newService: PersistenceService) {
        self.persistenceService = newService
        attachICloudObserver(nil)
        Log.persist.info("Swapped persistence backend → \(newService.notesDirectory.path, privacy: .public)")
    }

    public func attachICloudObserver(_ observer: iCloudChangeObserver?) {
        changeObserverCancellable?.cancel()
        changeObserver?.stop()
        changeObserver = observer
        guard let observer else { return }

        changeObserverCancellable = observer.changes.sink { [weak self] change in
            guard let self else { return }
            Task { @MainActor in self.applyExternalChange(change) }
        }
    }

    private func applyExternalChange(_ change: iCloudChangeObserver.Change) {
        switch change.kind {
        case .added, .updated:
            guard let service = persistenceService as? FilePersistenceService else { return }
            do {
                guard let resolved = try service.loadNote(id: change.noteID) else { return }
                let (updated, bucket) = resolved

                switch bucket {
                case .active:
                    if shouldApplyExternalUpdate(updated, currentlyAt: notes[change.noteID]) {
                        notes[change.noteID] = updated
                    }
                case .archived:
                    if !archivedNotes.isEmpty {
                        archivedNotes[change.noteID] = updated
                    }
                    // If it was active in memory and got archived elsewhere, evict.
                    notes.removeValue(forKey: change.noteID)
                case .trash:
                    if !trashedNotes.isEmpty {
                        trashedNotes[change.noteID] = updated
                    }
                    notes.removeValue(forKey: change.noteID)
                }
                Log.sync.debug("Pulled iCloud update for \(change.noteID, privacy: .public) (bucket: \(bucket.rawValue, privacy: .public))")
            } catch {
                Log.sync.error("Failed to load iCloud update for \(change.noteID, privacy: .public): \(error.localizedDescription)")
            }
        case .removed:
            // Deletion came from another device — drop it everywhere.
            if notes.removeValue(forKey: change.noteID) != nil
                || archivedNotes.removeValue(forKey: change.noteID) != nil
                || trashedNotes.removeValue(forKey: change.noteID) != nil {
                Log.sync.debug("Pulled iCloud deletion for \(change.noteID, privacy: .public)")
            }
        }
    }

    private func shouldApplyExternalUpdate(_ updated: NoteRecord, currentlyAt local: NoteRecord?) -> Bool {
        guard let local else { return true }
        if local.updatedAt >= updated.updatedAt
            && local.attributedBodyData == updated.attributedBodyData
            && local.title == updated.title
            && local.themeID == updated.themeID
            && local.isPinned == updated.isPinned {
            return false
        }
        return true
    }

    // MARK: - Active load

    public func loadAll() {
        do {
            let loaded = try persistenceService.loadActive()
            notes = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            Log.persist.info("Loaded \(loaded.count) active notes")
        } catch {
            Log.persist.error("Failed to load notes: \(error.localizedDescription)")
        }
    }

    // MARK: - On-demand bucket loads

    @discardableResult
    public func loadArchived() -> [NoteRecord] {
        do {
            let loaded = try persistenceService.loadArchived()
            archivedNotes = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            Log.persist.info("Loaded \(loaded.count) archived notes")
            return loaded
        } catch {
            Log.persist.error("Failed to load archived: \(error.localizedDescription)")
            return []
        }
    }

    @discardableResult
    public func loadTrashed() -> [NoteRecord] {
        do {
            let loaded = try persistenceService.loadTrashed()
            trashedNotes = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            Log.persist.info("Loaded \(loaded.count) trashed notes")
            return loaded
        } catch {
            Log.persist.error("Failed to load trashed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Create

    @discardableResult
    public func createNote(themeID: String = ThemeRegistry.defaultThemeID,
                           frame: PersistedRect = .default) -> NoteRecord {
        let maxOrder = notes.values.map(\.manualSortOrder).max() ?? -1
        var note = NoteRecord(themeID: themeID, frame: frame)
        note.manualSortOrder = maxOrder + 1
        notes[note.id] = note
        persistImmediately(note.id)
        Log.note.info("Created note \(note.id, privacy: .public)")
        return note
    }

    // MARK: - Mutators (active bucket)

    public func updateTitle(noteID: UUID, title: String) {
        guard var note = notes[noteID] else { return }
        note.title = title
        note.updatedAt = Date()
        notes[noteID] = note
        persistImmediately(noteID)
    }

    public func updateBody(noteID: UUID, attributedData: Data) {
        guard var note = notes[noteID] else { return }
        note.attributedBodyData = attributedData
        note.updatedAt = Date()
        notes[noteID] = note
        pendingNoteIDs.insert(noteID)
        bodySaveSubject.send(noteID)
    }

    public func updateTheme(noteID: UUID, themeID: String) {
        guard var note = notes[noteID] else { return }
        note.themeID = themeID
        note.updatedAt = Date()
        notes[noteID] = note
        persistImmediately(noteID)
    }

    public func updatePinned(noteID: UUID, isPinned: Bool) {
        guard var note = notes[noteID] else { return }
        note.isPinned = isPinned
        note.updatedAt = Date()
        notes[noteID] = note
        persistImmediately(noteID)
    }

    public func updateFrame(noteID: UUID, frame: PersistedRect) {
        guard var note = notes[noteID] else { return }
        note.frame = frame
        notes[noteID] = note
        pendingNoteIDs.insert(noteID)
        frameSaveSubject.send(noteID)
    }

    public func markClosed(noteID: UUID, isClosed: Bool) {
        guard var note = notes[noteID] else { return }
        note.isClosed = isClosed
        note.updatedAt = Date()
        notes[noteID] = note
        persistImmediately(noteID)
    }

    public func updateManualSortOrder(noteID: UUID, order: Int) {
        guard var note = notes[noteID] else { return }
        note.manualSortOrder = order
        notes[noteID] = note
        persistImmediately(noteID)
    }

    @discardableResult
    public func duplicateNote(noteID: UUID) -> NoteRecord? {
        guard let original = notes[noteID] else { return nil }
        var dup = NoteRecord(
            title: original.title,
            attributedBodyData: original.attributedBodyData,
            themeID: original.themeID
        )
        dup.updatedAt = Date()
        notes[dup.id] = dup
        persistImmediately(dup.id)
        Log.note.info("Duplicated note \(noteID, privacy: .public) → \(dup.id, privacy: .public)")
        return dup
    }

    // MARK: - Archive

    /// Move a note from Active to Archived. The note's files physically move
    /// into the `Archived/` subfolder on disk.
    public func archive(noteID: UUID) {
        guard var note = notes[noteID] else { return }
        note.isArchived = true
        note.updatedAt = Date()
        notes.removeValue(forKey: noteID)            // gone from active
        archivedNotes[noteID] = note                  // visible if archive view is open
        do {
            try persistenceService.save(note: note)   // writes into Archived/ and cleans Active
            Log.note.info("Archived note \(noteID, privacy: .public)")
        } catch {
            Log.persist.error("Archive failed for \(noteID, privacy: .public): \(error.localizedDescription)")
        }
    }

    /// Move a note from Archived back to Active.
    public func unarchive(noteID: UUID) {
        guard var note = archivedNotes[noteID] ?? loadOne(.archived, id: noteID) else { return }
        note.isArchived = false
        note.updatedAt = Date()
        archivedNotes.removeValue(forKey: noteID)
        notes[noteID] = note
        do {
            try persistenceService.save(note: note)
            Log.note.info("Unarchived note \(noteID, privacy: .public)")
        } catch {
            Log.persist.error("Unarchive failed for \(noteID, privacy: .public): \(error.localizedDescription)")
        }
    }

    // MARK: - Trash (soft delete)

    /// Soft-delete: move from Active (or Archived) to Trash. 30-day grace
    /// period before automatic permanent deletion.
    public func trash(noteID: UUID) {
        var src: NoteRecord? = notes[noteID]
            ?? archivedNotes[noteID]
            ?? loadOne(.active, id: noteID)
            ?? loadOne(.archived, id: noteID)
        guard var note = src else { return }
        _ = src

        note.isInTrash = true
        note.trashedAt = Date()
        note.isArchived = false
        note.updatedAt = Date()
        notes.removeValue(forKey: noteID)
        archivedNotes.removeValue(forKey: noteID)
        trashedNotes[noteID] = note
        do {
            try persistenceService.save(note: note)
            Log.note.info("Trashed note \(noteID, privacy: .public)")
        } catch {
            Log.persist.error("Trash failed for \(noteID, privacy: .public): \(error.localizedDescription)")
        }
    }

    /// Restore a trashed note back to Active.
    public func restoreFromTrash(noteID: UUID) {
        guard var note = trashedNotes[noteID] ?? loadOne(.trash, id: noteID) else { return }
        note.isInTrash = false
        note.trashedAt = nil
        note.updatedAt = Date()
        trashedNotes.removeValue(forKey: noteID)
        notes[noteID] = note
        do {
            try persistenceService.save(note: note)
            Log.note.info("Restored note \(noteID, privacy: .public)")
        } catch {
            Log.persist.error("Restore failed for \(noteID, privacy: .public): \(error.localizedDescription)")
        }
    }

    /// Permanently delete — irreversible.
    public func deleteForever(noteID: UUID) {
        notes.removeValue(forKey: noteID)
        archivedNotes.removeValue(forKey: noteID)
        trashedNotes.removeValue(forKey: noteID)
        pendingNoteIDs.remove(noteID)
        try? persistenceService.permanentlyDelete(noteID: noteID)
        Log.note.info("Permanently deleted \(noteID, privacy: .public)")
    }

    /// Empty the trash completely.
    public func emptyTrash() {
        let toRemove = Array(trashedNotes.keys)
        for id in toRemove { try? persistenceService.permanentlyDelete(noteID: id) }
        trashedNotes.removeAll()
        Log.note.info("Emptied trash (\(toRemove.count) notes)")
    }

    /// Auto-purge anything in the Trash older than 30 days. Safe to call on
    /// every launch.
    public func purgeOldTrash(maxAge seconds: TimeInterval = 30 * 24 * 60 * 60) {
        let cutoff = Date().addingTimeInterval(-seconds)
        try? persistenceService.purgeExpiredTrash(olderThan: cutoff)
        // Update in-memory trash mirror if it's currently loaded.
        if !trashedNotes.isEmpty {
            trashedNotes = trashedNotes.filter { (_, n) in (n.trashedAt ?? n.updatedAt) >= cutoff }
        }
    }

    // MARK: - Legacy compatibility shim

    /// Legacy entry point — old call sites use `deleteNote`. Now routes to
    /// `trash` so destructive actions go through the grace period.
    public func deleteNote(noteID: UUID) {
        trash(noteID: noteID)
    }

    // MARK: - Flush

    public func flushPendingSaves() {
        for noteID in pendingNoteIDs { persistImmediately(noteID) }
        if !pendingNoteIDs.isEmpty {
            Log.persist.error("Failed to flush \(self.pendingNoteIDs.count) notes")
        } else {
            Log.persist.info("Flushed all pending saves")
        }
    }

    // MARK: - Private

    private func setupDebounce() {
        bodySaveSubject
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] noteID in self?.persistImmediately(noteID) }
            .store(in: &cancellables)

        frameSaveSubject
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] noteID in self?.persistImmediately(noteID) }
            .store(in: &cancellables)
    }

    private func persistImmediately(_ noteID: UUID) {
        guard let note = notes[noteID] ?? archivedNotes[noteID] ?? trashedNotes[noteID] else { return }
        do {
            try persistenceService.save(note: note)
            pendingNoteIDs.remove(noteID)
        } catch {
            Log.persist.error("Save failed for \(noteID, privacy: .public): \(error.localizedDescription)")
        }
    }

    private func loadOne(_ bucket: StorageBucket, id: UUID) -> NoteRecord? {
        guard let svc = persistenceService as? FilePersistenceService else { return nil }
        return (try? svc.loadNote(id: id))?.note
    }
}
