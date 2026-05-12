import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - NoteRecord

public struct NoteRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var attributedBodyData: Data
    public var themeID: String
    public var isPinned: Bool
    public var frame: PersistedRect
    public var createdAt: Date
    public var updatedAt: Date
    public var isClosed: Bool
    public var isArchived: Bool
    public var manualSortOrder: Int

    /// Soft-deleted: file lives in the Trash/ subfolder of the notes directory
    /// and is purged after 30 days. Not loaded into the active store.
    public var isInTrash: Bool
    /// Set when the note moved into Trash; used for the 30-day purge window.
    public var trashedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String = "",
        attributedBodyData: Data = Data(),
        themeID: String = "yellow",
        isPinned: Bool = false,
        frame: PersistedRect = .default,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isClosed: Bool = false,
        isArchived: Bool = false,
        manualSortOrder: Int = 0,
        isInTrash: Bool = false,
        trashedAt: Date? = nil
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
        self.manualSortOrder = manualSortOrder
        self.isInTrash = isInTrash
        self.trashedAt = trashedAt
    }

    // Backward-compatible decoding: notes saved before isInTrash/trashedAt
    // existed simply default those fields.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id                 = try c.decode(UUID.self,          forKey: .id)
        self.title              = try c.decode(String.self,        forKey: .title)
        self.attributedBodyData = try c.decode(Data.self,          forKey: .attributedBodyData)
        self.themeID            = try c.decode(String.self,        forKey: .themeID)
        self.isPinned           = try c.decode(Bool.self,          forKey: .isPinned)
        self.frame              = try c.decode(PersistedRect.self, forKey: .frame)
        self.createdAt          = try c.decode(Date.self,          forKey: .createdAt)
        self.updatedAt          = try c.decode(Date.self,          forKey: .updatedAt)
        self.isClosed           = try c.decode(Bool.self,          forKey: .isClosed)
        self.isArchived         = try c.decode(Bool.self,          forKey: .isArchived)
        self.manualSortOrder    = try c.decode(Int.self,           forKey: .manualSortOrder)
        self.isInTrash          = try c.decodeIfPresent(Bool.self, forKey: .isInTrash) ?? false
        self.trashedAt          = try c.decodeIfPresent(Date.self, forKey: .trashedAt)
    }

    /// Full plain-text body for search.
    public var bodyPlainText: String {
        guard !attributedBodyData.isEmpty else { return "" }
        if let attrStr = try? NSAttributedString(
            data: attributedBodyData,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) {
            return attrStr.string
        }
        return ""
    }

    /// Plain-text excerpt extracted from the attributed body, for display in lists.
    public var bodyExcerpt: String {
        let plain = bodyPlainText.trimmingCharacters(in: .whitespacesAndNewlines)
        if plain.count > 140 { return String(plain.prefix(140)) + "…" }
        return plain
    }
}

// MARK: - PersistedRect

public struct PersistedRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public static let `default` = PersistedRect(x: 200, y: 400, width: 320, height: 320)

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(from rect: CGRect) {
        self.x = Double(rect.origin.x)
        self.y = Double(rect.origin.y)
        self.width = Double(rect.size.width)
        self.height = Double(rect.size.height)
    }
}
