import Foundation

public enum CubeThemePreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case aurora, ocean, sunset, starfield, blossom, forest
    case prism, moonstone, auroraFlow, slime
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .aurora: "极光"
        case .ocean: "海洋"
        case .sunset: "晚霞"
        case .starfield: "星空"
        case .blossom: "花海"
        case .forest: "森林"
        case .prism: "幻彩水晶"
        case .moonstone: "月光凝露"
        case .auroraFlow: "极光流体"
        case .slime: "史莱姆"
        }
    }
    private var colors: (String, String) {
        switch self {
        case .aurora: ("#65DEFF", "#B793FF")
        case .ocean: ("#4CB8FF", "#3EE4CF")
        case .sunset: ("#FFAA73", "#EE79B5")
        case .starfield: ("#8EAAFF", "#C185FF")
        case .blossom: ("#FF98CE", "#EAB0FF")
        case .forest: ("#70E5AB", "#B9E783")
        case .prism: ("#81DFFF", "#E5B2F8")
        case .moonstone: ("#D5E7FF", "#F3D9EF")
        case .auroraFlow: ("#64E4CF", "#ADA5FF")
        case .slime: ("#64E4CF", "#ADA5FF")
        }
    }
    public var primaryHex: String { colors.0 }
    public var secondaryHex: String { colors.1 }
    public var surfaceStyle: CubeSurfaceStyle {
        switch self {
        case .prism: .iridescent
        case .moonstone: .moonstone
        case .auroraFlow: .aurora
        case .slime: .slime
        default: .clear
        }
    }
    public func appearance(glowIntensity: Double) -> CubeAppearance {
        CubeAppearance(primaryHex: primaryHex, secondaryHex: secondaryHex, glowIntensity: glowIntensity, surfaceStyle: surfaceStyle)
    }
}

public struct CubeThemeCycle: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var themes: [CubeThemePreset]
    public var intervalSeconds: Int
    public init(isEnabled: Bool = false, themes: [CubeThemePreset] = [.aurora, .ocean, .sunset], intervalSeconds: Int = 10) {
        self.isEnabled = isEnabled
        self.themes = themes
        self.intervalSeconds = intervalSeconds
    }
    public func validate() throws {
        guard [10, 20].contains(intervalSeconds), Set(themes).count == themes.count,
              !isEnabled || themes.count >= 2 else { throw ConfigurationError.invalidThemeCycle }
    }
    public func next(after current: CubeThemePreset?) -> CubeThemePreset? {
        guard isEnabled, !themes.isEmpty else { return nil }
        guard let current, let index = themes.firstIndex(of: current) else { return themes.first }
        return themes[(index + 1) % themes.count]
    }
}
