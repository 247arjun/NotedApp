import Foundation
import Combine

// MARK: - iCloudChangeObserver

/// Watches the iCloud ubiquity container for note file changes coming from
/// other devices. Emits add / update / remove events keyed by note UUID so the
/// `NoteStore` can reload just the affected records.
///
/// Not `@MainActor` because `NSMetadataQuery`'s notifications carry
/// `Notification` (non-Sendable) and we want to handle them synchronously on
/// the queue Foundation delivers them on (`.main`) without hopping actors. The
/// `changes` subject is thread-safe; everything else is mutated only from main.
public final class iCloudChangeObserver: @unchecked Sendable {

    public struct Change: Sendable, Equatable {
        public enum Kind: Sendable, Equatable { case added, updated, removed }
        public let kind: Kind
        public let noteID: UUID
    }

    /// Subject other layers subscribe to.
    public let changes = PassthroughSubject<Change, Never>()

    private let lock = NSLock()
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var seenIDs: Set<UUID> = []

    public init() {}

    /// Begin observing. Pass the directory that notes are stored in (must be
    /// inside the iCloud ubiquity container). Safe to call repeatedly.
    public func start(notesDirectory: URL) {
        stop()

        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        // Match .json sidecars only — RTF body changes always accompany them.
        q.predicate = NSPredicate(
            format: "%K LIKE '*.json'",
            NSMetadataItemFSNameKey
        )
        q.notificationBatchingInterval = 0.5

        let nc = NotificationCenter.default
        // queue: .main delivers blocks synchronously on the main thread. We do
        // all work right here, no actor hop — that keeps the non-Sendable
        // `Notification` from crossing an isolation boundary.
        let gatheringObs = nc.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: q,
            queue: .main
        ) { [weak self] note in
            self?.handleResults(note)
        }
        let updateObs = nc.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: q,
            queue: .main
        ) { [weak self] note in
            self?.handleResults(note)
        }

        lock.lock()
        observers = [gatheringObs, updateObs]
        query = q
        lock.unlock()

        q.start()
        Log.sync.info("iCloud change observer started for \(notesDirectory.path, privacy: .public)")
    }

    public func stop() {
        lock.lock()
        let q = query
        let obs = observers
        query = nil
        observers.removeAll()
        seenIDs.removeAll()
        lock.unlock()

        q?.stop()
        for o in obs { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: - Handling

    private func handleResults(_ note: Notification) {
        guard let q = note.object as? NSMetadataQuery else { return }
        q.disableUpdates()
        defer { q.enableUpdates() }

        // Build the set of IDs currently in iCloud
        var currentIDs: Set<UUID> = []
        for i in 0..<q.resultCount {
            guard let item = q.result(at: i) as? NSMetadataItem,
                  let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String else { continue }
            let stem = (name as NSString).deletingPathExtension
            guard let id = UUID(uuidString: stem) else { continue }
            currentIDs.insert(id)
        }

        let userInfo = note.userInfo ?? [:]
        let added   = userInfo[NSMetadataQueryUpdateAddedItemsKey]   as? [NSMetadataItem] ?? []
        let changed = userInfo[NSMetadataQueryUpdateChangedItemsKey] as? [NSMetadataItem] ?? []
        let removed = userInfo[NSMetadataQueryUpdateRemovedItemsKey] as? [NSMetadataItem] ?? []

        if note.name == .NSMetadataQueryDidFinishGathering {
            lock.lock()
            let previous = seenIDs
            seenIDs = currentIDs
            lock.unlock()

            let toAdd    = currentIDs.subtracting(previous)
            let toRemove = previous.subtracting(currentIDs)
            for id in toAdd    { changes.send(.init(kind: .added,   noteID: id)) }
            for id in toRemove { changes.send(.init(kind: .removed, noteID: id)) }
            return
        }

        for item in added {
            if let id = id(of: item) {
                lock.lock(); seenIDs.insert(id); lock.unlock()
                changes.send(.init(kind: .added, noteID: id))
            }
        }
        for item in changed {
            if let id = id(of: item) {
                changes.send(.init(kind: .updated, noteID: id))
            }
        }
        for item in removed {
            if let id = id(of: item) {
                lock.lock(); seenIDs.remove(id); lock.unlock()
                changes.send(.init(kind: .removed, noteID: id))
            }
        }
    }

    private func id(of item: NSMetadataItem) -> UUID? {
        guard let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String else { return nil }
        let stem = (name as NSString).deletingPathExtension
        return UUID(uuidString: stem)
    }
}
