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
/// Layout:
/// ```
/// ~/Library/Application Support/Noted/Notes/
///     {uuid}.json          – metadata (NoteRecord minus body data)
///     {uuid}.rtf           – attributed body RTF data
/// ```
final class FilePersistenceService: PersistenceService {

    private let notesDirectory: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        notesDirectory = appSupport.appendingPathComponent("Noted/Notes", isDirectory: true)
        ensureDirectory()
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
