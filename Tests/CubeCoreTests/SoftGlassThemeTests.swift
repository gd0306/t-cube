import Foundation
import Testing
@testable import CubeCore

struct SoftGlassThemeTests {
    @Test func materialsAreIndependentOfEveryThemeAndPersistWithoutChangingDefaults() throws {
        #expect(CubeAppearance().material == .glass)
        #expect(CubeConfiguration().appearance.material == .glass)
        for theme in CubeThemePreset.allCases {
            let glass = theme.appearance(glowIntensity: 0.63, material: .glass)
            let slime = theme.appearance(glowIntensity: 0.63, material: .slime)
            #expect(glass.primaryHex == slime.primaryHex)
            #expect(glass.secondaryHex == slime.secondaryHex)
            #expect(glass.surfaceStyle == slime.surfaceStyle)
            #expect(slime.material == .slime)
        }
        var configuration = CubeConfiguration()
        configuration.appearance = CubeThemePreset.prism.appearance(glowIntensity: 0.63, material: .slime)
        configuration.themeCycle = CubeThemeCycle(isEnabled: true, themes: [.prism, .moonstone])
        let restored = try JSONDecoder().decode(CubeConfiguration.self, from: JSONEncoder().encode(configuration))
        #expect(restored == configuration)
        #expect(restored.appearance.material == .slime)
        #expect(restored.appearance.surfaceStyle == .iridescent)
        #expect(restored.appearance.glowIntensity == 0.63)
        #expect(restored.themeCycle.next(after: .prism) == .moonstone)
        try restored.validate()
    }

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
        #expect(restored.material == .glass)
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
