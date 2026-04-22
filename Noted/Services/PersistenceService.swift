import Foundation

// MARK: - PersistenceService Protocol

protocol PersistenceService {
    func loadNotes() throws -> [NoteRecord]
    func save(note: NoteRecord) throws
    func saveAll(notes: [NoteRecord]) throws
    func delete(noteID: UUID) throws
}

// MARK: - FilePersistenceService

/// File-based persistence.
///
/// Reads the save location from `AppSettings.shared.effectiveSaveDirectory`.
/// Supports migrating notes when the user changes the save location.
final class FilePersistenceService: PersistenceService {

    private var notesDirectory: URL

    init(directory: URL) {
        notesDirectory = directory
        ensureDirectory()
    }

    /// Migrate all note files from the current directory to a new one.
    /// Updates the internal directory pointer on success.
    func migrateNotes(to newDirectory: URL) throws {
        let fm = FileManager.default
        ensureDirectory()

        // Ensure destination exists
        try fm.createDirectory(at: newDirectory, withIntermediateDirectories: true)

        // Copy all files
        let contents = try fm.contentsOfDirectory(
            at: notesDirectory,
            includingPropertiesForKeys: nil
        )
        for file in contents {
            let dest = newDirectory.appendingPathComponent(file.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: file, to: dest)
        }

        // Remove old files after successful copy
        var failedRemovals: [URL] = []
        for file in contents {
            do {
                try fm.removeItem(at: file)
            } catch {
                Log.persist.error("Failed to remove old file \(file.lastPathComponent): \(error.localizedDescription)")
                failedRemovals.append(file)
            }
        }
        if !failedRemovals.isEmpty {
            Log.persist.warning("\(failedRemovals.count) old files could not be removed during migration")
        }

        notesDirectory = newDirectory
        Log.persist.info("Migrated notes to \(newDirectory.path)")
    }

    // MARK: - Load

    func loadNotes() throws -> [NoteRecord] {
        ensureDirectory()
        let contents = try FileManager.default.contentsOfDirectory(
            at: notesDirectory,
            includingPropertiesForKeys: nil
        )
        let jsonFiles = contents.filter { $0.pathExtension == "json" }

        var notes: [NoteRecord] = []
        for jsonURL in jsonFiles {
            do {
                let data = try Data(contentsOf: jsonURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                var note = try decoder.decode(NoteRecord.self, from: data)

                // Load RTF body
                let rtfURL = rtfFileURL(for: note.id)
                if FileManager.default.fileExists(atPath: rtfURL.path) {
                    note.attributedBodyData = try Data(contentsOf: rtfURL)
                }
                notes.append(note)
                Log.persist.debug("Loaded note \(note.id)")
            } catch {
                Log.persist.error("Failed to load note at \(jsonURL.lastPathComponent): \(error.localizedDescription)")
                // Continue loading other notes (§22.2 corruption handling).
            }
        }
        return notes
    }

    // MARK: - Save

    func save(note: NoteRecord) throws {
        ensureDirectory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // Write metadata (without heavy body data – body stored separately)
        var metaNote = note
        metaNote.attributedBodyData = Data() // strip body from JSON
        let jsonData = try encoder.encode(metaNote)
        try jsonData.write(to: jsonFileURL(for: note.id), options: .atomic)

        // Write RTF body
        if !note.attributedBodyData.isEmpty {
            try note.attributedBodyData.write(to: rtfFileURL(for: note.id), options: .atomic)
        }
        Log.persist.debug("Saved note \(note.id)")
    }

    func saveAll(notes: [NoteRecord]) throws {
        for note in notes {
            try save(note: note)
        }
    }

    // MARK: - Delete

    func delete(noteID: UUID) throws {
        let json = jsonFileURL(for: noteID)
        let rtf  = rtfFileURL(for: noteID)
        try? FileManager.default.removeItem(at: json)
        try? FileManager.default.removeItem(at: rtf)
        Log.persist.debug("Deleted note files for \(noteID)")
    }

    // MARK: - Helpers

    private func jsonFileURL(for id: UUID) -> URL {
        notesDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    private func rtfFileURL(for id: UUID) -> URL {
        notesDirectory.appendingPathComponent("\(id.uuidString).rtf")
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
    }
}
