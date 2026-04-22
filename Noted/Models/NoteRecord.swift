import Foundation

// MARK: - NoteRecord

struct NoteRecord: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var attributedBodyData: Data
    var themeID: String
    var isPinned: Bool
    var frame: PersistedRect
    var createdAt: Date
    var updatedAt: Date
    var isClosed: Bool
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        title: String = "",
        attributedBodyData: Data = Data(),
        themeID: String = "yellow",
        isPinned: Bool = false,
        frame: PersistedRect = .default,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isClosed: Bool = false,
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.attributedBodyData = attributedBodyData
        self.themeID = themeID
        self.isPinned = isPinned
        self.frame = frame
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isClosed = isClosed
        self.isArchived = isArchived
    }

    /// Plain-text excerpt extracted from the attributed body, for display in lists.
    var bodyExcerpt: String {
        guard !attributedBodyData.isEmpty else { return "" }
        if let attrStr = try? NSAttributedString(
            data: attributedBodyData,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) {
            let plain = attrStr.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if plain.count > 140 {
                return String(plain.prefix(140)) + "…"
            }
            return plain
        }
        return ""
    }
}

// MARK: - PersistedRect

struct PersistedRect: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let `default` = PersistedRect(x: 200, y: 400, width: 320, height: 320)

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(from rect: CGRect) {
        self.x = Double(rect.origin.x)
        self.y = Double(rect.origin.y)
        self.width = Double(rect.size.width)
        self.height = Double(rect.size.height)
    }
}
