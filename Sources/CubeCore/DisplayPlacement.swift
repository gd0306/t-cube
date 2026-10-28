import Foundation

/// Display identity is separate from its current coordinate system and resolution.
public struct DesktopDisplay: Equatable, Sendable {
    public let id: String
    public let visibleFrame: CGRect

    public init(id: String, visibleFrame: CGRect) {
        self.id = id
        self.visibleFrame = visibleFrame
    }
}

public enum DesktopPlacementError: Error, LocalizedError {
    case invalidData
    public var errorDescription: String? { "桌面位置记录无效；原文件已保留。" }
}

public struct NormalizedDisplayPosition: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
}

public struct DesktopPlacementState: Codable, Equatable, Sendable {
    public private(set) var version = 1
    public private(set) var positions: [String: NormalizedDisplayPosition] = [:]
    public private(set) var preferredDisplayID: String?

    public init() {}

    public func validate() throws {
        guard version == 1, positions.keys.allSatisfy({ !$0.isEmpty }),
              preferredDisplayID.map({ positions[$0] != nil }) ?? true,
              positions.values.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else {
            throw DesktopPlacementError.invalidData
        }
    }

    public mutating func record(frame: CGRect, displays: [DesktopDisplay]) throws {
        guard Self.valid(frame), !displays.isEmpty,
              displays.allSatisfy({ !$0.id.isEmpty && Self.valid($0.visibleFrame) }),
              let visible = WindowPlacement.visibleScreen(for: frame, screens: displays.map(\.visibleFrame)),
              let display = displays.first(where: { $0.visibleFrame == visible }) else { throw DesktopPlacementError.invalidData }
        let origin = WindowPlacement.clamp(frame.origin, size: frame.size, screens: [visible])
        let availableX = max(0, visible.width - frame.width)
        let availableY = max(0, visible.height - frame.height)
        positions[display.id] = NormalizedDisplayPosition(x: availableX > 0 ? Double((origin.x - visible.minX) / availableX) : 0,
                                                        y: availableY > 0 ? Double((origin.y - visible.minY) / availableY) : 0)
        preferredDisplayID = display.id
    }

    /// Merely falling back never mutates preferredDisplayID or disconnected records.
    /// The first supplied display is the primary display.
    public func restoredFrame(size: CGSize, displays: [DesktopDisplay]) -> CGRect? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              let primary = displays.first, displays.allSatisfy({ Self.valid($0.visibleFrame) }),
              let preferredDisplayID, let remembered = positions[preferredDisplayID] else { return nil }
        let display = displays.first(where: { $0.id == preferredDisplayID }) ?? primary
        let position = positions[display.id] ?? remembered
        return CGRect(x: display.visibleFrame.minX + max(0, display.visibleFrame.width - size.width) * position.x,
                      y: display.visibleFrame.minY + max(0, display.visibleFrame.height - size.height) * position.y,
                      width: size.width, height: size.height)
    }

    private static func valid(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite && frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0
    }
}

/// Independent from launcher configuration, with atomic writes and no corrupt-file fallback.
public struct DesktopPositionStore: Sendable {
    public let url: URL

    public init(url: URL = DesktopPositionStore.defaultURL) { self.url = url }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("T-Cube/desktop-positions.json")
    }

    public func load() throws -> DesktopPlacementState {
        guard FileManager.default.fileExists(atPath: url.path) else { return DesktopPlacementState() }
        let state = try JSONDecoder().decode(DesktopPlacementState.self, from: Data(contentsOf: url))
        try state.validate()
        return state
    }

    public func save(_ state: DesktopPlacementState) throws {
        try state.validate()
        let data = try JSONEncoder().encode(state)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
