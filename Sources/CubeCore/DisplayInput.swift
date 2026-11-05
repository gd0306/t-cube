import Foundation

public enum DisplayInputSource: String, Codable, Sendable { case typeC, hdmi }

public struct DisplayInputMapping: Codable, Equatable, Sendable {
    public let typeC: UInt16
    public let hdmi: UInt16
    public init?(typeC: UInt16, hdmi: UInt16) {
        guard typeC != hdmi else { return nil }
        self.typeC = typeC; self.hdmi = hdmi
    }
    public func source(for value: UInt16) -> DisplayInputSource? {
        value == typeC ? .typeC : value == hdmi ? .hdmi : nil
    }
    public func value(for source: DisplayInputSource) -> UInt16 { source == .typeC ? typeC : hdmi }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeC = try container.decode(UInt16.self, forKey: .typeC)
        let hdmi = try container.decode(UInt16.self, forKey: .hdmi)
        guard typeC != hdmi else { throw DecodingError.dataCorruptedError(forKey: .hdmi, in: container, debugDescription: "Input codes must differ") }
        self.typeC = typeC; self.hdmi = hdmi
    }
}

public struct DDCInputValue: Equatable, Sendable {
    public let current: UInt16
    public let maximum: UInt16
}

public enum DDCInputCodec {
    public static let readRequest: [UInt8] = [0x82, 0x01, 0x60, 0xDC]
    public static func writeRequest(value: UInt16) -> [UInt8] {
        let bytes: [UInt8] = [0x84, 0x03, 0x60, UInt8(value >> 8), UInt8(value & 0xFF)]
        return bytes + [bytes.reduce(UInt8(0x6E ^ 0x51), ^)]
    }
    public static func parseReply(_ bytes: [UInt8]) -> DDCInputValue? {
        guard bytes.count == 11, bytes[0] == 0x6E, bytes[1] == 0x88, bytes[2] == 2,
              bytes[3] == 0, bytes[4] == 0x60, (bytes[5] == 0 || bytes[5] == 1),
              bytes.dropLast().reduce(UInt8(0x50), ^) == bytes[10] else { return nil }
        return DDCInputValue(current: UInt16(bytes[8]) << 8 | UInt16(bytes[9]), maximum: UInt16(bytes[6]) << 8 | UInt16(bytes[7]))
    }
}

public struct DisplayInputStore {
    private struct Document: Codable { let version: Int; var mappings: [String: DisplayInputMapping] }
    public let url: URL
    public init(url: URL) { self.url = url }
    private func load() throws -> Document {
        guard FileManager.default.fileExists(atPath: url.path) else { return Document(version: 1, mappings: [:]) }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 1_048_576 else { throw CocoaError(.fileReadCorruptFile) }
        var doc = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        guard doc.version == 1, doc.mappings.count <= 256 else { throw CocoaError(.fileReadCorruptFile) }
        var canonical: [String: DisplayInputMapping] = [:]
        for (key, mapping) in doc.mappings {
            guard let uuid = UUID(uuidString: key), canonical[uuid.uuidString] == nil else { throw CocoaError(.fileReadCorruptFile) }
            canonical[uuid.uuidString] = mapping
        }
        doc.mappings = canonical
        return doc
    }
    public func mapping(for uuid: String) throws -> DisplayInputMapping? { try load().mappings[uuid.uppercased()] }
    public func save(_ mapping: DisplayInputMapping, for uuid: String) throws {
        guard let uuid = UUID(uuidString: uuid) else { throw CocoaError(.fileWriteInvalidFileName) }
        var doc = try load()
        doc.mappings[uuid.uuidString] = mapping
        guard doc.mappings.count <= 256 else { throw CocoaError(.fileWriteOutOfSpace) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(doc)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
