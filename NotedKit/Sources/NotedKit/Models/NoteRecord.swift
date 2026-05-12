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
        manualSortOrder: Int = 0
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
