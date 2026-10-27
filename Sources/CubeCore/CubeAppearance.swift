import Foundation

public enum CubeSurfaceStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case clear, iridescent, moonstone, aurora, slime
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .clear: "通透柔边"
        case .iridescent: "幻彩折光"
        case .moonstone: "月光柔雾"
        case .aurora: "极光流体"
        case .slime: "史莱姆"
        }
    }
}

public struct CubeAppearance: Codable, Equatable, Sendable {
    public var primaryHex: String
    public var secondaryHex: String
    public var glowIntensity: Double
    public var surfaceStyle: CubeSurfaceStyle

    public init(primaryHex: String = "#65DEFF", secondaryHex: String = "#B793FF", glowIntensity: Double = 0.55, surfaceStyle: CubeSurfaceStyle = .clear) {
        self.primaryHex = primaryHex
        self.secondaryHex = secondaryHex
        self.glowIntensity = glowIntensity
        self.surfaceStyle = surfaceStyle
    }

    private enum CodingKeys: String, CodingKey { case primaryHex, secondaryHex, glowIntensity, surfaceStyle }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primaryHex = try container.decode(String.self, forKey: .primaryHex)
        secondaryHex = try container.decode(String.self, forKey: .secondaryHex)
        glowIntensity = try container.decode(Double.self, forKey: .glowIntensity)
        surfaceStyle = try container.decodeIfPresent(CubeSurfaceStyle.self, forKey: .surfaceStyle) ?? .clear
    }

    public func validate() throws {
        func valid(_ value: String) -> Bool {
            value.utf8.count == 7 && value.first == "#" && value.dropFirst().allSatisfy { "0123456789abcdefABCDEF".contains($0) }
        }
        guard valid(primaryHex), valid(secondaryHex), glowIntensity.isFinite, (0...1).contains(glowIntensity) else {
            throw ConfigurationError.invalidAppearance
        }
    }
}
