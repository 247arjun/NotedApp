import Foundation

// MARK: - PersistenceService protocol

public protocol PersistenceService: AnyObject, Sendable {
    func loadNotes() throws -> [NoteRecord]
    func save(note: NoteRecord) throws
    func saveAll(notes: [NoteRecord]) throws
    func delete(noteID: UUID) throws
    /// Re-point this service at a new directory and move any notes already
    /// stored at the old location.
    func migrateNotes(to newDirectory: URL) throws
    /// Currently-active notes directory.
    var notesDirectory: URL { get }
}

// MARK: - FilePersistenceService

/// File-based persistence using `NSFileCoordinator` for safe concurrent access.
///
/// Works for both local directories and iCloud Drive ubiquity containers — the
/// difference is purely *where* the directory points. iCloud handles syncing
/// behind the scenes; this layer just ensures every read/write is coordinated.
public final class FilePersistenceService: PersistenceService, @unchecked Sendable {

    public private(set) var notesDirectory: URL
    private let coordinator = NSFileCoordinator()
    private let queue = DispatchQueue(label: "com.arjun.Noted.persistence", qos: .userInitiated)

    public init(directory: URL) {
        self.notesDirectory = directory
        ensureDirectory()
    }

    // MARK: - Migration

    public func migrateNotes(to newDirectory: URL) throws {
        let fm = FileManager.default
        ensureDirectory()
        try fm.createDirectory(at: newDirectory, withIntermediateDirectories: true)

        let oldDir = notesDirectory
        var copyError: Error?

        var readErr: NSError?
        coordinator.coordinate(readingItemAt: oldDir, options: [], error: &readErr) { srcURL in
            do {
                let contents = try fm.contentsOfDirectory(at: srcURL, includingPropertiesForKeys: nil)
                for file in contents {
                    let dest = newDirectory.appendingPathComponent(file.lastPathComponent)
                    var writeErr: NSError?
                    coordinator.coordinate(writingItemAt: dest, options: .forReplacing, error: &writeErr) { destURL in
                        do {
                            if fm.fileExists(atPath: destURL.path) {
                                try fm.removeItem(at: destURL)
                            }
                            try fm.copyItem(at: file, to: destURL)
                        } catch {
                            copyError = error
                        }
                    }
                    if let writeErr { throw writeErr }
                }
            } catch {
                copyError = error
            }
        }
        if let readErr { throw readErr }
        if let copyError { throw copyError }

        // Best-effort delete of originals
        if let contents = try? fm.contentsOfDirectory(at: oldDir, includingPropertiesForKeys: nil) {
            for file in contents { try? fm.removeItem(at: file) }
        }

        notesDirectory = newDirectory
        Log.persist.info("Migrated notes to \(newDirectory.path, privacy: .public)")
    }

    // MARK: - Load

    public func loadNotes() throws -> [NoteRecord] {
        ensureDirectory()
        let fm = FileManager.default
        var notes: [NoteRecord] = []
        var loadError: Error?

        var coordErr: NSError?
        coordinator.coordinate(readingItemAt: notesDirectory, options: [], error: &coordErr) { dirURL in
            do {
                let contents = try fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
                let jsonFiles = contents.filter { $0.pathExtension == "json" }
                for jsonURL in jsonFiles {
                    do {
                        var data = Data()
                        var innerErr: NSError?
                        coordinator.coordinate(readingItemAt: jsonURL, options: [], error: &innerErr) { url in
                            data = (try? Data(contentsOf: url)) ?? Data()
                        }
                        if let innerErr { throw innerErr }
                        guard !data.isEmpty else { continue }

                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        var note = try decoder.decode(NoteRecord.self, from: data)

                        // Load RTF body alongside
                        let rtfURL = dirURL.appendingPathComponent("\(note.id.uuidString).rtf")
                        if fm.fileExists(atPath: rtfURL.path) {
                            var rtfData = Data()
                            var rtfErr: NSError?
                            coordinator.coordinate(readingItemAt: rtfURL, options: [], error: &rtfErr) { url in
                                rtfData = (try? Data(contentsOf: url)) ?? Data()
                            }
                            if rtfErr == nil { note.attributedBodyData = rtfData }
                        }
                        notes.append(note)
                    } catch {
                        Log.persist.error("Failed to load \(jsonURL.lastPathComponent, privacy: .public): \(error.localizedDescription)")
                    }
                }
            } catch {
                loadError = error
            }
        }
        if let coordErr { throw coordErr }
        if let loadError { throw loadError }
        return notes
    }

    /// Reload a single note from disk, if it exists. Returns nil if missing.
    public func loadNote(id: UUID) throws -> NoteRecord? {
        ensureDirectory()
        let fm = FileManager.default
        let jsonURL = jsonFileURL(for: id)
        guard fm.fileExists(atPath: jsonURL.path) else { return nil }

        var note: NoteRecord?
        var thrown: Error?
        var coordErr: NSError?
        coordinator.coordinate(readingItemAt: jsonURL, options: [], error: &coordErr) { url in
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                var loaded = try decoder.decode(NoteRecord.self, from: data)

                let rtfURL = rtfFileURL(for: id)
                if fm.fileExists(atPath: rtfURL.path),
                   let rtf = try? Data(contentsOf: rtfURL) {
                    loaded.attributedBodyData = rtf
                }
                note = loaded
            } catch {
                thrown = error
            }
        }
        if let coordErr { throw coordErr }
        if let thrown { throw thrown }
        return note
    }

    // MARK: - Save

    public func save(note: NoteRecord) throws {
        ensureDirectory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        var meta = note
        meta.attributedBodyData = Data() // body stored in companion .rtf
        let jsonData = try encoder.encode(meta)

        try coordinatedWrite(to: jsonFileURL(for: note.id), data: jsonData)

        if !note.attributedBodyData.isEmpty {
            try coordinatedWrite(to: rtfFileURL(for: note.id), data: note.attributedBodyData)
        }
        Log.persist.debug("Saved note \(note.id, privacy: .public)")
    }

    public func saveAll(notes: [NoteRecord]) throws {
        for note in notes { try save(note: note) }
    }

    // MARK: - Delete

    public func delete(noteID: UUID) throws {
        let fm = FileManager.default
        for url in [jsonFileURL(for: noteID), rtfFileURL(for: noteID)] {
            var coordErr: NSError?
            coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordErr) { u in
                try? fm.removeItem(at: u)
            }
            if let coordErr { throw coordErr }
        }
        Log.persist.debug("Deleted note files for \(noteID, privacy: .public)")
    }

    // MARK: - Helpers

    private func coordinatedWrite(to url: URL, data: Data) throws {
        var thrown: Error?
        var coordErr: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordErr) { u in
            do {
                try data.write(to: u, options: .atomic)
            } catch {
                thrown = error
            }
        }
        if let coordErr { throw coordErr }
        if let thrown { throw thrown }
    }

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
