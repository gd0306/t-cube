import Foundation

public enum ConfigurationError: Error, Equatable, Sendable, LocalizedError {
    case groupFull, duplicateItem, invalidSlot, emptySlot, occupiedSlot, invalidName, invalidSlotCount
    case invalidGroups, invalidItem, invalidScale, invalidPosition, invalidAppearance
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .groupFull: "分组已满，每组最多四个入口。"
        case .duplicateItem: "此分组已有相同入口。"
        case .invalidSlot: "入口位置无效。"
        case .emptySlot: "此位置没有入口。"
        case .occupiedSlot: "此位置已有入口，请选择重新选择目标来替换。"
        case .invalidName: "名称不能为空。"
        case .invalidSlotCount: "每组必须有四个位置。"
        case .invalidGroups: "配置必须包含六个分组。"
        case .invalidItem: "入口必须是本地应用或文件夹。"
        case .invalidScale: "立方体尺寸超出允许范围。"
        case .invalidPosition: "窗口位置无效。"
        case .invalidAppearance: "主题颜色或光晕强度无效。"
        case .unsupportedVersion(let version): "不支持的配置版本：\(version)。"
        }
    }
}

public struct LauncherItem: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case application, folder }
    public let id: UUID
    public var url: URL
    public var name: String
    public var kind: Kind
    public var bookmark: Data?

    public init(id: UUID = UUID(), url: URL, name: String, kind: Kind, bookmark: Data? = nil) {
        self.id = id
        self.url = url
        self.name = name
        self.kind = kind
        self.bookmark = bookmark
    }

    fileprivate var targetPath: String { url.standardizedFileURL.path }
    fileprivate func validate() throws {
        guard url.isFileURL else { throw ConfigurationError.invalidItem }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConfigurationError.invalidName
        }
    }
}

public struct FaceGroup: Codable, Equatable, Sendable {
    public private(set) var name: String
    public private(set) var slots: [LauncherItem?]

    public init(name: String, slots: [LauncherItem?] = Array(repeating: nil, count: 4)) throws {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.slots = slots
        try validate()
    }

    fileprivate func validate() throws {
        guard slots.count == 4 else { throw ConfigurationError.invalidSlotCount }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConfigurationError.invalidName
        }
        let items = slots.compactMap { $0 }
        for item in items { try item.validate() }
        guard Set(items.map(\.targetPath)).count == items.count,
              Set(items.map(\.id)).count == items.count else { throw ConfigurationError.duplicateItem }
    }

    fileprivate mutating func rename(to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ConfigurationError.invalidName }
        self.name = trimmed
    }

    fileprivate mutating func add(_ item: LauncherItem) throws {
        try item.validate()
        guard !slots.compactMap({ $0 }).contains(where: { $0.targetPath == item.targetPath || $0.id == item.id }) else {
            throw ConfigurationError.duplicateItem
        }
        guard let slot = slots.firstIndex(where: { $0 == nil }) else { throw ConfigurationError.groupFull }
        slots[slot] = item
    }

    fileprivate mutating func place(_ item: LauncherItem, slot: Int, replacing: Bool) throws {
        guard slots.indices.contains(slot) else { throw ConfigurationError.invalidSlot }
        guard replacing || slots[slot] == nil else { throw ConfigurationError.occupiedSlot }
        var candidate = self
        candidate.slots[slot] = item
        try candidate.validate()
        self = candidate
    }

    fileprivate mutating func remove(slot: Int) throws {
        guard slots.indices.contains(slot) else { throw ConfigurationError.invalidSlot }
        guard slots[slot] != nil else { throw ConfigurationError.emptySlot }
        slots[slot] = nil
    }

    fileprivate mutating func move(from source: Int, to destination: Int) throws {
        guard slots.indices.contains(source), slots.indices.contains(destination) else {
            throw ConfigurationError.invalidSlot
        }
        guard slots[source] != nil else { throw ConfigurationError.emptySlot }
        let moved = slots.remove(at: source)
        slots.insert(moved, at: destination)
    }

    private enum CodingKeys: String, CodingKey { case name, slots }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(name: container.decode(String.self, forKey: .name),
                      slots: container.decode([LauncherItem?].self, forKey: .slots))
    }
}

public struct WindowPosition: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct CubeConfiguration: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let scaleRange: ClosedRange<Double> = 0.65...1.6
    public let version: Int
    public private(set) var groups: [CubeFace: FaceGroup]
    public var themeID: String
    public var appearance: CubeAppearance
    public var scale: Double
    /// AppKit screen coordinates, at the panel's bottom-left corner. Nil means center on first launch.
    public var windowPosition: WindowPosition?

    public init() {
        version = Self.currentVersion
        groups = Dictionary(uniqueKeysWithValues: zip(CubeFace.allCases, ["常用", "开发", "设计", "办公", "文件夹", "更多"]).map {
            ($0.0, try! FaceGroup(name: $0.1))
        })
        themeID = "graphite"
        appearance = CubeAppearance()
        scale = 1
        windowPosition = nil
    }

    public func group(for face: CubeFace) -> FaceGroup { groups[face]! }
    public mutating func add(_ item: LauncherItem, to face: CubeFace) throws { try groups[face]!.add(item) }
    /// Sets only the requested slot; rejected changes preserve every original slot.
    public mutating func place(_ item: LauncherItem, to face: CubeFace, slot: Int, replacing: Bool = false) throws {
        try groups[face]!.place(item, slot: slot, replacing: replacing)
    }
    public mutating func remove(from face: CubeFace, slot: Int) throws { try groups[face]!.remove(slot: slot) }
    /// Remove and insert a slot, shifting intervening slots and preserving empty positions.
    public mutating func move(in face: CubeFace, from source: Int, to destination: Int) throws {
        try groups[face]!.move(from: source, to: destination)
    }
    public mutating func rename(_ face: CubeFace, to name: String) throws { try groups[face]!.rename(to: name) }

    public func validate() throws {
        guard version == Self.currentVersion else { throw ConfigurationError.unsupportedVersion(version) }
        guard Set(groups.keys) == Set(CubeFace.allCases) else { throw ConfigurationError.invalidGroups }
        for group in groups.values { try group.validate() }
        try appearance.validate()
        guard scale.isFinite, Self.scaleRange.contains(scale) else { throw ConfigurationError.invalidScale }
        if let position = windowPosition, !position.x.isFinite || !position.y.isFinite {
            throw ConfigurationError.invalidPosition
        }
    }

    private enum CodingKeys: String, CodingKey { case version, groups, themeID, appearance, scale, windowPosition }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else { throw ConfigurationError.unsupportedVersion(version) }
        groups = try container.decode([CubeFace: FaceGroup].self, forKey: .groups)
        themeID = try container.decode(String.self, forKey: .themeID)
        appearance = try container.decodeIfPresent(CubeAppearance.self, forKey: .appearance) ?? CubeAppearance()
        scale = try container.decode(Double.self, forKey: .scale)
        windowPosition = try container.decodeIfPresent(WindowPosition.self, forKey: .windowPosition)
        try validate()
    }
}

public struct ConfigurationStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("T-Cube", isDirectory: true)
            .appendingPathComponent("configuration.json")
    }

    public func load() throws -> CubeConfiguration {
        do { return try JSONDecoder().decode(CubeConfiguration.self, from: Data(contentsOf: url)) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return CubeConfiguration() }
    }

    /// Existing malformed/unsupported data blocks saving, even after an earlier failed load.
    /// The caller must explicitly move that file aside before starting a new configuration.
    public func save(_ configuration: CubeConfiguration) throws {
        try configuration.validate()
        _ = try load()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
