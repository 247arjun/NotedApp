import Foundation
import Combine

// MARK: - NoteStore

/// Single source of truth for all note data.
/// Publishes changes via `@Published` for observation.
final class NoteStore: ObservableObject {

    @Published private(set) var notes: [UUID: NoteRecord] = [:]

    private let persistenceService: PersistenceService

    // Debounce subjects
    private let bodySaveSubject  = PassthroughSubject<UUID, Never>()
    private let frameSaveSubject = PassthroughSubject<UUID, Never>()
    private var cancellables = Set<AnyCancellable>()

    // Track dirty notes whose saves are pending
    private var pendingNoteIDs = Set<UUID>()

    init(persistenceService: PersistenceService) {
        self.persistenceService = persistenceService
        setupDebounce()
    }

    // MARK: - Load

    func loadAll() {
        do {
            let loaded = try persistenceService.loadNotes()
            var dict: [UUID: NoteRecord] = [:]
            for note in loaded {
                dict[note.id] = note
            }
            notes = dict
            Log.persist.info("Loaded \(loaded.count) notes from disk")
        } catch {
            Log.persist.error("Failed to load notes: \(error.localizedDescription)")
        }
    }

    // MARK: - Create

    @discardableResult
    func createNote(frame: PersistedRect = .default) -> NoteRecord {
        let note = NoteRecord(frame: frame)
        notes[note.id] = note
        persistImmediately(note.id)
        Log.note.info("Created note \(note.id)")
        return note
    }

    // MARK: - Mutators

    func updateTitle(noteID: UUID, title: String) {
        guard var note = notes[noteID] else { return }
        note.title = title
        note.updatedAt = Date()
        notes[noteID] = note
        persistImmediately(noteID)
    }

    func updateBody(noteID: UUID, attributedData: Data) {
        guard var note = notes[noteID] else { return }
        note.attributedBodyData = attributedData
        note.updatedAt = Date()
        notes[noteID] = note
        pendingNoteIDs.insert(noteID)
        bodySaveSubject.send(noteID)
    }

    func updateTheme(noteID: UUID, themeID: String) {
        guard var note = notes[noteID] else { return }
        note.themeID = themeID
        note.updatedAt = Date()
        notes[noteID] = note
        persistImmediately(noteID)
    }

    func updatePinned(noteID: UUID, isPinned: Bool) {
        guard var note = notes[noteID] else { return }
        note.isPinned = isPinned
        note.updatedAt = Date()
        notes[noteID] = note
        persistImmediately(noteID)
    }

    func updateFrame(noteID: UUID, frame: PersistedRect) {
        guard var note = notes[noteID] else { return }
        note.frame = frame
        notes[noteID] = note
        pendingNoteIDs.insert(noteID)
        frameSaveSubject.send(noteID)
    }

    func markClosed(noteID: UUID, isClosed: Bool) {
        guard var note = notes[noteID] else { return }
        note.isClosed = isClosed
        note.updatedAt = Date()
        notes[noteID] = note
        persistImmediately(noteID)
    }

    @discardableResult
    func duplicateNote(noteID: UUID) -> NoteRecord? {
        guard let original = notes[noteID] else { return nil }
        var dup = NoteRecord(
            title: original.title,
            attributedBodyData: original.attributedBodyData,
            themeID: original.themeID
        )
        dup.updatedAt = Date()
        notes[dup.id] = dup
        persistImmediately(dup.id)
        Log.note.info("Duplicated note \(noteID) → \(dup.id)")
        return dup
    }

    func deleteNote(noteID: UUID) {
        notes.removeValue(forKey: noteID)
        pendingNoteIDs.remove(noteID)
        try? persistenceService.delete(noteID: noteID)
        Log.note.info("Deleted note \(noteID)")
    }

    // MARK: - Flush

    /// Synchronously flush all pending debounced saves.
    func flushPendingSaves() {
        for noteID in pendingNoteIDs {
            persistImmediately(noteID)
        }
        pendingNoteIDs.removeAll()
        Log.persist.info("Flushed all pending saves")
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
            Log.persist.error("Save failed for \(noteID): \(error.localizedDescription)")
            // Keep note in memory – will retry on future save events (§29.1).
        }
    }
}
