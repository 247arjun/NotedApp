import Foundation
import Combine
import NotedKit

/// Holds the iOS app's persistent state: the `NoteStore`, the persistence
/// backend, and the iCloud change observer. Always uses iCloud Drive when
/// signed in; falls back to local storage otherwise.
@MainActor
final class AppModel: ObservableObject, NoteIntentHost {

    static let shared = AppModel()

    let noteStore: NoteStore
    private var persistence: FilePersistenceService
    private var iCloudObserver: iCloudChangeObserver?

    @Published private(set) var usingICloud: Bool = false

    /// Navigation hook for `OpenNoteIntent`. The RootView observes this and
    /// pushes the editor when it changes.
    @Published var pendingOpenNoteID: UUID?

    private init() {
        let directory = AppModel.resolveStartupDirectory()
        let service = FilePersistenceService(directory: directory)
        self.persistence = service
        self.noteStore = NoteStore(persistenceService: service)
        self.usingICloud = StorageLocationResolver.iCloudAvailable
            && directory.path.contains("Mobile Documents")

        noteStore.loadAll()
        noteStore.purgeOldTrash()
        installICloudObserverIfNeeded(directory: directory)

        IntentHostRegistry.current = self
    }

    /// `NoteIntentHost` conformance — called from `OpenNoteIntent`.
    func openNote(id: UUID) {
        pendingOpenNoteID = id
    }

    static func resolveStartupDirectory() -> URL {
        if let url = StorageLocationResolver.iCloudDirectory() { return url }
        return StorageLocationResolver.defaultLocalDirectory()
    }

    private func installICloudObserverIfNeeded(directory: URL) {
        guard usingICloud else { return }
        let observer = iCloudChangeObserver()
        observer.start(notesDirectory: directory)
        noteStore.attachICloudObserver(observer)
        self.iCloudObserver = observer
    }

    /// Re-resolve the storage location (e.g. if iCloud became available after
    /// launch). Called from a pull-to-refresh action in the list view.
    func refresh() {
        let newDir = AppModel.resolveStartupDirectory()
        let nowOnICloud = StorageLocationResolver.iCloudAvailable
            && newDir.path.contains("Mobile Documents")

        if persistence.notesDirectory != newDir {
            let newService = FilePersistenceService(directory: newDir)
            self.persistence = newService
            noteStore.swapPersistenceService(newService)
            iCloudObserver?.stop()
            iCloudObserver = nil
            if nowOnICloud {
                let obs = iCloudChangeObserver()
                obs.start(notesDirectory: newDir)
                noteStore.attachICloudObserver(obs)
                self.iCloudObserver = obs
            } else {
                noteStore.attachICloudObserver(nil)
            }
            usingICloud = nowOnICloud
        }
        noteStore.loadAll()
    }
}
