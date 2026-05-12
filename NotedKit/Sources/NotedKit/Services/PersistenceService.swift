import Foundation

// MARK: - StorageBucket

/// Where a note's files live on disk inside the notes directory.
///
/// The directory layout in iCloud Drive (or local fallback) is:
/// ```
///   <notesDirectory>/
///   ├── <uuid>.json + <uuid>.rtf      (active)
///   ├── Archived/
///   │   └── <uuid>.json + <uuid>.rtf  (archived; not loaded on launch)
///   └── Trash/
///       └── <uuid>.json + <uuid>.rtf  (soft-deleted; purged after 30 days)
/// ```
public enum StorageBucket: String, Sendable, CaseIterable {
    case active   = ""
    case archived = "Archived"
    case trash    = "Trash"

    /// Path component appended to the notes directory for this bucket.
    public var folderName: String { rawValue }
}

// MARK: - PersistenceService

public protocol PersistenceService: AnyObject, Sendable {
    /// Active notes only — what's loaded on launch. Fast.
    func loadActive() throws -> [NoteRecord]
    /// Notes in the Archived/ subfolder. On-demand (separate view).
    func loadArchived() throws -> [NoteRecord]
    /// Notes in the Trash/ subfolder. On-demand (separate view).
    func loadTrashed() throws -> [NoteRecord]

    /// Persist a note into its appropriate bucket, which is inferred from
    /// `note.isInTrash` / `note.isArchived`. Removes any stale file in other
    /// buckets to avoid duplicate copies after a move.
    func save(note: NoteRecord) throws

    /// Move a note's files between buckets without touching the JSON content
    /// (other than updating the in-memory `NoteRecord` if you re-save it).
    func move(noteID: UUID, to bucket: StorageBucket) throws

    /// Delete a note's files from every bucket. Irreversible.
    func permanentlyDelete(noteID: UUID) throws

    /// Remove any Trash notes whose `trashedAt` is older than `cutoff`.
    func purgeExpiredTrash(olderThan cutoff: Date) throws

    /// Re-point this service at a new directory and move all subfolders too.
    func migrateNotes(to newDirectory: URL) throws

    var notesDirectory: URL { get }
}

// MARK: - FilePersistenceService

/// File-based persistence using `NSFileCoordinator` for safe concurrent access.
/// Works identically against an iCloud ubiquity container and a local folder.
public final class FilePersistenceService: PersistenceService, @unchecked Sendable {

    public private(set) var notesDirectory: URL
    private let coordinator = NSFileCoordinator()

    public init(directory: URL) {
        self.notesDirectory = directory
        ensureBuckets()
    }

    // MARK: - Public load API

    public func loadActive()   throws -> [NoteRecord] { try load(in: .active)   }
    public func loadArchived() throws -> [NoteRecord] { try load(in: .archived) }
    public func loadTrashed()  throws -> [NoteRecord] { try load(in: .trash)    }

    // MARK: - Save

    public func save(note: NoteRecord) throws {
        ensureBuckets()
        let bucket = bucket(for: note)

        // Encode metadata (without body data — body lives in the .rtf sidecar)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var meta = note
        meta.attributedBodyData = Data()
        let jsonData = try encoder.encode(meta)

        // Write the pair into the target bucket
        try coordinatedWrite(to: jsonURL(for: note.id, in: bucket), data: jsonData)
        if !note.attributedBodyData.isEmpty {
            try coordinatedWrite(to: rtfURL(for: note.id, in: bucket), data: note.attributedBodyData)
        } else {
            // Remove any stale rtf if the body was emptied
            try? coordinatedRemove(rtfURL(for: note.id, in: bucket))
        }

        // Remove any leftover copies in OTHER buckets (e.g. note that just
        // moved from Active → Archived had files in Active that need to go).
        for other in StorageBucket.allCases where other != bucket {
            try? coordinatedRemove(jsonURL(for: note.id, in: other))
            try? coordinatedRemove(rtfURL(for: note.id, in: other))
        }

        Log.persist.debug("Saved \(note.id, privacy: .public) into bucket '\(bucket.rawValue, privacy: .public)'")
    }

    // MARK: - Bucket movement

    public func move(noteID: UUID, to bucket: StorageBucket) throws {
        ensureBuckets()
        // Find where the files currently live.
        var source: StorageBucket? = nil
        for b in StorageBucket.allCases {
            if FileManager.default.fileExists(atPath: jsonURL(for: noteID, in: b).path) {
                source = b
                break
            }
        }
        guard let src = source, src != bucket else { return }

        for ext in ["json", "rtf"] {
            let s = notesDirectory.appendingPathComponent(src.folderName, isDirectory: true)
                                  .appendingPathComponent("\(noteID.uuidString).\(ext)")
            let d = notesDirectory.appendingPathComponent(bucket.folderName, isDirectory: true)
                                  .appendingPathComponent("\(noteID.uuidString).\(ext)")
            if FileManager.default.fileExists(atPath: s.path) {
                try coordinatedMove(from: s, to: d)
            }
        }
        Log.persist.debug("Moved \(noteID, privacy: .public) from '\(src.rawValue, privacy: .public)' to '\(bucket.rawValue, privacy: .public)'")
    }

    // MARK: - Permanent delete

    public func permanentlyDelete(noteID: UUID) throws {
        for b in StorageBucket.allCases {
            try? coordinatedRemove(jsonURL(for: noteID, in: b))
            try? coordinatedRemove(rtfURL(for: noteID, in: b))
        }
        Log.persist.debug("Permanently deleted \(noteID, privacy: .public)")
    }

    // MARK: - 30-day Trash purge

    public func purgeExpiredTrash(olderThan cutoff: Date) throws {
        let trashed = (try? loadTrashed()) ?? []
        for note in trashed where (note.trashedAt ?? note.updatedAt) < cutoff {
            try? permanentlyDelete(noteID: note.id)
        }
    }

    // MARK: - Migration

    public func migrateNotes(to newDirectory: URL) throws {
        let fm = FileManager.default
        ensureBuckets()
        try fm.createDirectory(at: newDirectory, withIntermediateDirectories: true)

        let oldDir = notesDirectory

        // Create matching subfolders at destination
        for b in StorageBucket.allCases where !b.folderName.isEmpty {
            try? fm.createDirectory(
                at: newDirectory.appendingPathComponent(b.folderName, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        // Copy everything — top-level files plus Archived/ and Trash/ contents.
        try copyAllNoteFiles(from: oldDir, to: newDirectory)
        for b in StorageBucket.allCases where !b.folderName.isEmpty {
            let src = oldDir.appendingPathComponent(b.folderName, isDirectory: true)
            let dst = newDirectory.appendingPathComponent(b.folderName, isDirectory: true)
            if fm.fileExists(atPath: src.path) {
                try copyAllNoteFiles(from: src, to: dst)
            }
        }

        // Best-effort cleanup of originals.
        for b in StorageBucket.allCases {
            let dir = oldDir.appendingPathComponent(b.folderName, isDirectory: true)
            if let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for f in contents where f.pathExtension == "json" || f.pathExtension == "rtf" {
                    try? fm.removeItem(at: f)
                }
            }
        }

        notesDirectory = newDirectory
        ensureBuckets()
        Log.persist.info("Migrated notes (all buckets) to \(newDirectory.path, privacy: .public)")
    }

    // MARK: - Helpers

    /// Load a single note by id, searching all buckets. Useful for live iCloud
    /// updates where we know the UUID but not where it lives.
    public func loadNote(id: UUID) throws -> (note: NoteRecord, bucket: StorageBucket)? {
        for b in StorageBucket.allCases {
            let jURL = jsonURL(for: id, in: b)
            if FileManager.default.fileExists(atPath: jURL.path) {
                if let n = try readNote(at: jURL, rtfAt: rtfURL(for: id, in: b)) {
                    return (n, b)
                }
            }
        }
        return nil
    }

    private func load(in bucket: StorageBucket) throws -> [NoteRecord] {
        ensureBuckets()
        let fm = FileManager.default
        let dir = notesDirectory.appendingPathComponent(bucket.folderName, isDirectory: true)
        var notes: [NoteRecord] = []
        var loadError: Error?

        var coordErr: NSError?
        coordinator.coordinate(readingItemAt: dir, options: [], error: &coordErr) { dirURL in
            do {
                let contents = try fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
                for jsonURL in contents where jsonURL.pathExtension == "json" {
                    let rtfURL = dirURL.appendingPathComponent(
                        (jsonURL.lastPathComponent as NSString).deletingPathExtension + ".rtf"
                    )
                    do {
                        if let note = try readNote(at: jsonURL, rtfAt: rtfURL) {
                            notes.append(note)
                        }
                    } catch {
                        Log.persist.error("Failed to load \(jsonURL.lastPathComponent, privacy: .public) in '\(bucket.rawValue, privacy: .public)': \(error.localizedDescription)")
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

    private func readNote(at jsonURL: URL, rtfAt rtfURL: URL) throws -> NoteRecord? {
        let fm = FileManager.default
        var note: NoteRecord?
        var thrown: Error?
        var coordErr: NSError?
        coordinator.coordinate(readingItemAt: jsonURL, options: [], error: &coordErr) { url in
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                var loaded = try decoder.decode(NoteRecord.self, from: data)
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

    // MARK: - Coordinated IO primitives

    private func coordinatedWrite(to url: URL, data: Data) throws {
        var thrown: Error?
        var coordErr: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordErr) { u in
            do { try data.write(to: u, options: .atomic) }
            catch { thrown = error }
        }
        if let coordErr { throw coordErr }
        if let thrown { throw thrown }
    }

    private func coordinatedRemove(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var thrown: Error?
        var coordErr: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordErr) { u in
            do { try FileManager.default.removeItem(at: u) }
            catch { thrown = error }
        }
        if let coordErr { throw coordErr }
        if let thrown { throw thrown }
    }

    private func coordinatedMove(from src: URL, to dst: URL) throws {
        // Ensure destination parent exists.
        try? FileManager.default.createDirectory(
            at: dst.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var thrown: Error?
        var coordErr: NSError?
        coordinator.coordinate(
            writingItemAt: src, options: .forMoving,
            writingItemAt: dst, options: .forReplacing,
            error: &coordErr
        ) { s, d in
            do {
                if FileManager.default.fileExists(atPath: d.path) {
                    try FileManager.default.removeItem(at: d)
                }
                try FileManager.default.moveItem(at: s, to: d)
            } catch { thrown = error }
        }
        if let coordErr { throw coordErr }
        if let thrown { throw thrown }
    }

    private func copyAllNoteFiles(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)
        for f in contents where f.pathExtension == "json" || f.pathExtension == "rtf" {
            let dest = dst.appendingPathComponent(f.lastPathComponent)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: f, to: dest)
        }
    }

    // MARK: - Internal path helpers

    private func bucket(for note: NoteRecord) -> StorageBucket {
        if note.isInTrash  { return .trash }
        if note.isArchived { return .archived }
        return .active
    }

    private func jsonURL(for id: UUID, in bucket: StorageBucket) -> URL {
        notesDirectory.appendingPathComponent(bucket.folderName, isDirectory: true)
                      .appendingPathComponent("\(id.uuidString).json")
    }

    private func rtfURL(for id: UUID, in bucket: StorageBucket) -> URL {
        notesDirectory.appendingPathComponent(bucket.folderName, isDirectory: true)
                      .appendingPathComponent("\(id.uuidString).rtf")
    }

    private func ensureBuckets() {
        let fm = FileManager.default
        try? fm.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        for b in StorageBucket.allCases where !b.folderName.isEmpty {
            let url = notesDirectory.appendingPathComponent(b.folderName, isDirectory: true)
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
