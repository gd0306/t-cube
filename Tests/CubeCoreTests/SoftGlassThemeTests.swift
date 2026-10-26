import Foundation
import Testing
@testable import CubeCore

struct SoftGlassThemeTests {
    @Test func newThemesKeepTheirMaterialWhenSavedAndCycled() throws {
        var config = CubeConfiguration()
        config.appearance = CubeThemePreset.prism.appearance(glowIntensity: 0.48)
        config.themeCycle = CubeThemeCycle(isEnabled: true, themes: [.prism, .moonstone, .auroraFlow], intervalSeconds: 20)
        let restored = try JSONDecoder().decode(CubeConfiguration.self, from: JSONEncoder().encode(config))
        #expect(restored == config)
        #expect(restored.appearance.surfaceStyle == .iridescent)
        #expect(restored.themeCycle.next(after: .prism) == .moonstone)
        #expect(CubeThemePreset.moonstone.appearance(glowIntensity: 0.48).surfaceStyle == .moonstone)
        #expect(CubeThemePreset.auroraFlow.appearance(glowIntensity: 0.48).surfaceStyle == .aurora)
    }

    @Test func oldAppearanceLoadsClearGlassWithoutChangingColors() throws {
        let json = Data(##"{"primaryHex":"#345678","secondaryHex":"#ABCDEF","glowIntensity":0.42}"##.utf8)
        let restored = try JSONDecoder().decode(CubeAppearance.self, from: json)
        #expect(restored.surfaceStyle == .clear)
        #expect(restored.primaryHex == "#345678")
        #expect(restored.secondaryHex == "#ABCDEF")
        #expect(restored.glowIntensity == 0.42)
    }

    @Test func materialChoiceSurvivesCustomColors() throws {
        var appearance = CubeThemePreset.moonstone.appearance(glowIntensity: 0.7)
        appearance.primaryHex = "#11CCAA"
        let restored = try JSONDecoder().decode(CubeAppearance.self, from: JSONEncoder().encode(appearance))
        #expect(restored.surfaceStyle == .moonstone)
        #expect(restored.primaryHex == "#11CCAA")
        try restored.validate()
    }
}
