import Foundation

public struct SnippetField: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var label: String
    public var value: String

    public init(id: UUID = UUID(), label: String = "", value: String = "") {
        self.id = id
        self.label = label
        self.value = value
    }
}

public struct TextSnippet: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var group: String
    public var body: String
    public var fields: [SnippetField]
    public var isFavorite: Bool
    public var isTemplate: Bool

    public init(id: UUID = UUID(), title: String = "", group: String = "", body: String = "",
                fields: [SnippetField] = [], isFavorite: Bool = false, isTemplate: Bool = false) {
        self.id = id
        self.title = title
        self.group = group
        self.body = body
        self.fields = fields
        self.isFavorite = isFavorite
        self.isTemplate = isTemplate
    }

    private enum CodingKeys: String, CodingKey { case id, title, group, body, fields, isFavorite, isTemplate }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        group = try values.decode(String.self, forKey: .group)
        body = try values.decode(String.self, forKey: .body)
        fields = try values.decode([SnippetField].self, forKey: .fields)
        isFavorite = try values.decode(Bool.self, forKey: .isFavorite)
        isTemplate = try values.decodeIfPresent(Bool.self, forKey: .isTemplate) ?? false
    }

    public var fullText: String {
        var parts = body.snippetIsBlank ? [] : [body]
        parts.append(contentsOf: fields.filter { !$0.value.snippetIsBlank }.map { "\($0.label)：\($0.value)" })
        return parts.joined(separator: "\n")
    }
}

public enum SnippetLibraryError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedVersion(Int)
    case duplicateSnippetID(UUID)
    case duplicateFieldID(UUID)
    case emptyTitle
    case emptyContent
    case emptyFieldLabel

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "资料库版本 \(version) 暂不受支持，请使用更新版本的 T-Cube。"
        case .duplicateSnippetID: "资料库中存在重复的内容标识。"
        case .duplicateFieldID: "资料库中存在重复的字段标识。"
        case .emptyTitle: "请填写内容标题。"
        case .emptyContent: "请填写正文或至少一个字段的值。"
        case .emptyFieldLabel: "有值的字段需要填写名称。"
        }
    }
}

public struct SnippetLibrary: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var items: [TextSnippet]

    public init(items: [TextSnippet] = []) {
        self.items = items
    }

    public func filtered(query: String, group: String? = nil, favoritesOnly: Bool = false) -> [TextSnippet] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = items.filter { snippet in
            guard group == nil || snippet.group == group else { return false }
            guard !favoritesOnly || snippet.isFavorite else { return false }
            guard !query.isEmpty else { return true }
            let searchable = [snippet.title, snippet.body, snippet.group] + snippet.fields.flatMap { [$0.label, $0.value] }
            return searchable.contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        return matches.filter(\.isFavorite) + matches.filter { !$0.isFavorite }
    }

    public func validate() throws {
        guard version == 1 else { throw SnippetLibraryError.unsupportedVersion(version) }
        var snippetIDs = Set<UUID>()
        var fieldIDs = Set<UUID>()
        for snippet in items {
            guard snippetIDs.insert(snippet.id).inserted else { throw SnippetLibraryError.duplicateSnippetID(snippet.id) }
            guard !snippet.title.snippetIsBlank else { throw SnippetLibraryError.emptyTitle }
            guard !snippet.body.snippetIsBlank || snippet.fields.contains(where: { !$0.value.snippetIsBlank }) else {
                throw SnippetLibraryError.emptyContent
            }
            for field in snippet.fields {
                guard fieldIDs.insert(field.id).inserted else { throw SnippetLibraryError.duplicateFieldID(field.id) }
                guard field.value.snippetIsBlank || !field.label.snippetIsBlank else { throw SnippetLibraryError.emptyFieldLabel }
            }
        }
    }
}

public struct SnippetStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("T-Cube", isDirectory: true)
            .appendingPathComponent("content-library.json")
    }

    public func load() throws -> SnippetLibrary {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return SnippetLibrary()
        }
        let library = try JSONDecoder().decode(SnippetLibrary.self, from: data)
        try library.validate()
        return library
    }

    public func save(_ library: SnippetLibrary) throws {
        try library.validate()
        // Refuse to replace damaged data or a format this app cannot understand.
        _ = try load()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(library)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

private extension String {
    var snippetIsBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
