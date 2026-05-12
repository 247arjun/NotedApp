import Foundation
import AppIntents

// MARK: - IntentHostRegistry

/// Glue between the App Intents (which can be invoked from anywhere — Siri,
/// Spotlight, Shortcuts.app, system-wide keyboard) and the running app.
///
/// Each platform's app registers a concrete host at startup. Intents call
/// `IntentHostRegistry.current?.noteStore` to read/write notes and
/// `IntentHostRegistry.current?.openNote(id:)` to bring a note to the front.
@MainActor
public enum IntentHostRegistry {
    public static var current: (any NoteIntentHost)?
}

@MainActor
public protocol NoteIntentHost: AnyObject {
    var noteStore: NoteStore { get }
    /// Bring the note's editor surface to the user. macOS opens a note
    /// window; iOS navigates the main scene.
    func openNote(id: UUID)
}

// MARK: - NoteEntity

/// Represents a note in the App Intents type system. Lets users pick notes
/// in Shortcuts builder, search results, etc.
public struct NoteEntity: AppEntity, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var excerpt: String

    public init(id: UUID, title: String, excerpt: String) {
        self.id = id
        self.title = title
        self.excerpt = excerpt
    }

    public init(record: NoteRecord) {
        self.id = record.id
        self.title = record.title.isEmpty ? "Untitled" : record.title
        self.excerpt = record.bodyExcerpt
    }

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Note")
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(excerpt)")
    }

    public static let defaultQuery = NoteEntityQuery()
}

// MARK: - NoteEntityQuery

public struct NoteEntityQuery: EntityQuery, EntityStringQuery {
    public init() {}

    @MainActor
    public func entities(for identifiers: [NoteEntity.ID]) async throws -> [NoteEntity] {
        guard let store = IntentHostRegistry.current?.noteStore else { return [] }
        return identifiers.compactMap { id in
            store.notes[id].map(NoteEntity.init(record:))
        }
    }

    @MainActor
    public func suggestedEntities() async throws -> [NoteEntity] {
        guard let store = IntentHostRegistry.current?.noteStore else { return [] }
        return store.notes.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(10)
            .map(NoteEntity.init(record:))
    }

    @MainActor
    public func entities(matching string: String) async throws -> [NoteEntity] {
        guard let store = IntentHostRegistry.current?.noteStore else { return [] }
        let needle = string.lowercased()
        return store.notes.values
            .filter {
                $0.title.lowercased().contains(needle)
                || $0.bodyPlainText.lowercased().contains(needle)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(NoteEntity.init(record:))
    }
}

// MARK: - CreateNoteIntent

public struct CreateNoteIntent: AppIntent {
    public static let title: LocalizedStringResource = "New Note"
    public static let description = IntentDescription("Create a new note in Noted.")
    public static let openAppWhenRun: Bool = false

    @Parameter(title: "Text", description: "Initial body text for the note.", default: "")
    public var text: String

    @Parameter(title: "Title", description: "Optional title.", default: "")
    public var noteTitle: String

    public init() {}

    public init(text: String = "", title: String = "") {
        self.text = text
        self.noteTitle = title
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<NoteEntity> & ProvidesDialog {
        guard let host = IntentHostRegistry.current else {
            throw NoteIntentError.appNotReady
        }

        let store = host.noteStore
        let note = store.createNote()
        if !noteTitle.isEmpty {
            store.updateTitle(noteID: note.id, title: noteTitle)
        }
        if !text.isEmpty {
            let attr = NSAttributedString(string: text, attributes: [
                .font: PlatformFont.systemFont(ofSize: AppSettings.shared.defaultFontSize)
            ])
            let data = (try? attr.data(
                from: NSRange(location: 0, length: attr.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )) ?? Data()
            store.updateBody(noteID: note.id, attributedData: data)
        }
        store.flushPendingSaves()

        let entity = NoteEntity(id: note.id,
                                title: noteTitle.isEmpty ? "Untitled" : noteTitle,
                                excerpt: text)
        return .result(value: entity, dialog: "Created \(entity.title)")
    }
}

// MARK: - SearchNotesIntent

public struct SearchNotesIntent: AppIntent {
    public static let title: LocalizedStringResource = "Search Notes"
    public static let description = IntentDescription("Search the bodies and titles of your notes.")
    public static let openAppWhenRun: Bool = false

    @Parameter(title: "Query")
    public var query: String

    public init() {}
    public init(query: String) { self.query = query }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<[NoteEntity]> {
        guard let store = IntentHostRegistry.current?.noteStore else {
            return .result(value: [])
        }
        let needle = query.lowercased()
        let hits = store.notes.values
            .filter {
                $0.title.lowercased().contains(needle)
                || $0.bodyPlainText.lowercased().contains(needle)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(NoteEntity.init(record:))
        return .result(value: hits)
    }
}

// MARK: - OpenNoteIntent

public struct OpenNoteIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Note"
    public static let description = IntentDescription("Open a note in Noted.")
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "Note")
    public var note: NoteEntity

    public init() {}
    public init(note: NoteEntity) { self.note = note }

    @MainActor
    public func perform() async throws -> some IntentResult {
        IntentHostRegistry.current?.openNote(id: note.id)
        return .result()
    }
}

// MARK: - Errors

public enum NoteIntentError: Error, CustomLocalizedStringResourceConvertible {
    case appNotReady

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotReady: return "Noted isn't ready yet. Try again in a moment."
        }
    }
}
