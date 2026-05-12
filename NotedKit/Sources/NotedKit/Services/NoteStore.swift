import Foundation
import Combine

// MARK: - NoteStore

/// Single source of truth for all note data.
/// Publishes changes via `@Published` for observation from SwiftUI and AppKit.
@MainActor
public final class NoteStore: ObservableObject {

    @Published public private(set) var notes: [UUID: NoteRecord] = [:]

    public private(set) var persistenceService: PersistenceService

    // Debounce subjects
    private let bodySaveSubject  = PassthroughSubject<UUID, Never>()
    private let frameSaveSubject = PassthroughSubject<UUID, Never>()
    private var cancellables = Set<AnyCancellable>()

    // Track dirty notes whose saves are pending
    private var pendingNoteIDs = Set<UUID>()

    // Optional iCloud change observer
    private var changeObserver: iCloudChangeObserver?
    private var changeObserverCancellable: AnyCancellable?

    public init(persistenceService: PersistenceService) {
        self.persistenceService = persistenceService
        setupDebounce()
    }

    // MARK: - Backend swap

    /// Replace the persistence backend at runtime (e.g. user toggled iCloud
    /// sync). The caller is responsible for any one-time file migration.
    public func swapPersistenceService(_ newService: PersistenceService) {
        self.persistenceService = newService
        // Detach any iCloud observer that may have been tied to the old service.
        attachICloudObserver(nil)
        Log.persist.info("Swapped persistence backend → \(newService.notesDirectory.path, privacy: .public)")
    }

    /// Attach (or detach with nil) an iCloud change observer so external edits
    /// propagate into the store. Pass `nil` to stop observing.
    public func attachICloudObserver(_ observer: iCloudChangeObserver?) {
        // Tear down any previous subscription
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
                if let updated = try service.loadNote(id: change.noteID) {
                    // Skip if this is just our own recent write echoing back
                    if let local = notes[change.noteID],
                       local.updatedAt >= updated.updatedAt,
                       local.attributedBodyData == updated.attributedBodyData,
                       local.title == updated.title,
                       local.themeID == updated.themeID,
                       local.isPinned == updated.isPinned {
                        return
                    }
                    notes[change.noteID] = updated
                    Log.sync.debug("Pulled iCloud update for \(change.noteID, privacy: .public)")
                }
            } catch {
                Log.sync.error("Failed to load iCloud update for \(change.noteID, privacy: .public): \(error.localizedDescription)")
            }
        case .removed:
            if notes[change.noteID] != nil {
                notes.removeValue(forKey: change.noteID)
                Log.sync.debug("Pulled iCloud deletion for \(change.noteID, privacy: .public)")
            }
        }
    }

    // MARK: - Load

    public func loadAll() {
        do {
            let loaded = try persistenceService.loadNotes()
            var dict: [UUID: NoteRecord] = [:]
            for note in loaded { dict[note.id] = note }
            notes = dict
            Log.persist.info("Loaded \(loaded.count) notes from disk")
        } catch {
            Log.persist.error("Failed to load notes: \(error.localizedDescription)")
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

    // MARK: - Mutators

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

    public func deleteNote(noteID: UUID) {
        notes.removeValue(forKey: noteID)
        pendingNoteIDs.remove(noteID)
        try? persistenceService.delete(noteID: noteID)
        Log.note.info("Deleted note \(noteID, privacy: .public)")
    }

    // MARK: - Flush

    /// Synchronously flush all pending debounced saves.
    public func flushPendingSaves() {
        for noteID in pendingNoteIDs {
            persistImmediately(noteID)
        }
        if !pendingNoteIDs.isEmpty {
            let remaining = pendingNoteIDs
            Log.persist.error("Failed to flush \(remaining.count) notes")
        } else {
            Log.persist.info("Flushed all pending saves")
        }
    }

    // MARK: - Private

    private func setupDebounce() {
        bodySaveSubject
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] noteID in
                self?.persistImmediately(noteID)
            }
            .store(in: &cancellables)

        frameSaveSubject
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] noteID in
                self?.persistImmediately(noteID)
            }
            .store(in: &cancellables)
    }

    private func persistImmediately(_ noteID: UUID) {
        guard let note = notes[noteID] else { return }
        do {
            try persistenceService.save(note: note)
            pendingNoteIDs.remove(noteID)
        } catch {
            Log.persist.error("Save failed for \(noteID, privacy: .public): \(error.localizedDescription)")
        }
    }
}
