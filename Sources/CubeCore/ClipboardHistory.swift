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

public struct ClipboardHistoryImage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let pngData: Data
    public let thumbnailPNG: Data
    public let width: Int
    public let height: Int
    public let capturedAt: Date
}

/// Session-only text and image history. Intentionally has no persistence or archive conformance.
public struct ClipboardHistory: Equatable, Sendable {
    public static let maximumEntryCount = 100
    public static let maximumEntryUTF8Bytes = 64 * 1024
    public static let maximumTotalUTF8Bytes = 2 * 1024 * 1024
    public private(set) var entries: [ClipboardHistoryEntry] = []
    public private(set) var totalUTF8Bytes = 0

    public static let maximumImageCount = 10
    public static let maximumImageBytes = 8 * 1024 * 1024
    public static let maximumTotalImageBytes = 32 * 1024 * 1024
    public static let maximumImagePixels = 16_000_000
    public static let maximumThumbnailBytes = 256 * 1024
    public private(set) var images: [ClipboardHistoryImage] = []
    public private(set) var totalImageBytes = 0

    public init() {}

    /// Selection order is always the visible newest-first history order.
    /// Transforms affect the preview/output only, never the recorded entries.
    public func mergedText(selectedIDs: Set<UUID>, query: String, trimLines: Bool, collapseBlankLines: Bool) -> String? {
        let chosen = filtered(query: query).filter { selectedIDs.contains($0.id) }
        guard !chosen.isEmpty else { return nil }
        var output = chosen.map(\.text).joined(separator: "\n")
        if trimLines || collapseBlankLines {
            var lines = output.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: .newlines)
            if trimLines { lines = lines.map { $0.trimmingCharacters(in: .whitespaces) } }
            if collapseBlankLines {
                var previousBlank = false
                lines = lines.filter { line in
                    let blank = line.trimmingCharacters(in: .whitespaces).isEmpty
                    defer { previousBlank = blank }
                    return !blank || !previousBlank
                }
            }
            output = lines.joined(separator: "\n")
        }
        return Self.accepts(output) ? output : nil
    }

    @discardableResult
    public mutating func recordImage(pngData: Data, thumbnailPNG: Data, width: Int, height: Int, at date: Date = Date()) -> Bool {
        guard !pngData.isEmpty, pngData.count <= Self.maximumImageBytes,
              !thumbnailPNG.isEmpty, thumbnailPNG.count <= Self.maximumThumbnailBytes,
              width > 0, height > 0, width <= Self.maximumImagePixels / height else { return false }
        let id: UUID
        if let duplicate = images.firstIndex(where: { $0.pngData == pngData }) {
            let previous = images.remove(at: duplicate)
            totalImageBytes -= previous.pngData.count
            id = previous.id
        } else { id = UUID() }
        images.insert(ClipboardHistoryImage(id: id, pngData: pngData, thumbnailPNG: thumbnailPNG,
            width: width, height: height, capturedAt: date), at: 0)
        totalImageBytes += pngData.count
        while images.count > Self.maximumImageCount || totalImageBytes > Self.maximumTotalImageBytes {
            totalImageBytes -= images.removeLast().pngData.count
        }
        return true
    }

    @discardableResult
    public mutating func deleteImage(_ id: UUID) -> Bool {
        guard let index = images.firstIndex(where: { $0.id == id }) else { return false }
        totalImageBytes -= images.remove(at: index).pngData.count
        return true
    }

    public mutating func clearImages() {
        images.removeAll()
        totalImageBytes = 0
    }

    public mutating func clearText() {
        entries.removeAll()
        totalUTF8Bytes = 0
    }

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

    /// Editing is session-only and never evicts an unrelated record to make room.
    @discardableResult
    public mutating func updateText(id: UUID, text: String) -> Bool {
        guard Self.accepts(text), let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        let previous = entries[index]
        let bytes = totalUTF8Bytes - previous.text.utf8.count + text.utf8.count
        guard bytes <= Self.maximumTotalUTF8Bytes else { return false }
        entries[index] = ClipboardHistoryEntry(id: id, text: text, capturedAt: previous.capturedAt)
        totalUTF8Bytes = bytes
        return true
    }

    @discardableResult
    public mutating func delete(_ id: UUID) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        totalUTF8Bytes -= entries.remove(at: index).text.utf8.count
        return true
    }

    public mutating func clear() {
        clearText()
        clearImages()
    }
}
