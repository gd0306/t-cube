import Foundation

public struct ClipboardHistoryEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let capturedAt: Date

    public init(id: UUID = UUID(), text: String, capturedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.capturedAt = capturedAt
    }
}

/// Session-only text history. Intentionally has no persistence or archive conformance.
public struct ClipboardHistory: Equatable, Sendable {
    public static let maximumEntryCount = 100
    public static let maximumEntryUTF8Bytes = 64 * 1024
    public static let maximumTotalUTF8Bytes = 2 * 1024 * 1024
    public private(set) var entries: [ClipboardHistoryEntry] = []
    public private(set) var totalUTF8Bytes = 0

    public init() {}

    public static func accepts(_ text: String) -> Bool {
        text.utf8.count <= maximumEntryUTF8Bytes && !text.utf8.contains(0) &&
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @discardableResult
    public mutating func record(_ text: String, at date: Date = Date()) -> Bool {
        guard Self.accepts(text) else { return false }
        // Swift String equality normalizes Unicode. History deduplicates exact bytes.
        let duplicate = entries.firstIndex { $0.text.utf8.elementsEqual(text.utf8) }
        let id: UUID
        if let duplicate {
            let previous = entries.remove(at: duplicate)
            totalUTF8Bytes -= previous.text.utf8.count
            id = previous.id
        } else { id = UUID() }
        entries.insert(ClipboardHistoryEntry(id: id, text: text, capturedAt: date), at: 0)
        totalUTF8Bytes += text.utf8.count
        while entries.count > Self.maximumEntryCount || totalUTF8Bytes > Self.maximumTotalUTF8Bytes {
            totalUTF8Bytes -= entries.removeLast().text.utf8.count
        }
        return true
    }

    public func filtered(query: String) -> [ClipboardHistoryEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    @discardableResult
    public mutating func delete(_ id: UUID) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        totalUTF8Bytes -= entries.remove(at: index).text.utf8.count
        return true
    }

    public mutating func clear() {
        entries.removeAll()
        totalUTF8Bytes = 0
    }
}
