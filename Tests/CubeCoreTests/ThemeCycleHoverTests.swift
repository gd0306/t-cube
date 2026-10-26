import Foundation
import Testing
@testable import CubeCore

struct ThemeCycleHoverTests {
    @Test func cyclesSelectedThemesInOrderAndWraps() {
        let cycle = CubeThemeCycle(isEnabled: true, themes: [.ocean, .starfield, .blossom], intervalSeconds: 20)
        #expect(cycle.next(after: nil) == .ocean)
        #expect(cycle.next(after: .ocean) == .starfield)
        #expect(cycle.next(after: .starfield) == .blossom)
        #expect(cycle.next(after: .blossom) == .ocean)
        #expect(cycle.next(after: .sunset) == .ocean)
    }

    @Test func settingsRoundTripWithoutChangingEntriesOrManualColors() throws {
        var config = CubeConfiguration()
        try config.rename(.front, to: "我的入口")
        config.themeCycle = CubeThemeCycle(isEnabled: true, themes: [.ocean, .blossom], intervalSeconds: 20)
        config.hover = CubeHoverSettings(isEnabled: true, multiplier: 4.0)
        let restored = try JSONDecoder().decode(CubeConfiguration.self, from: JSONEncoder().encode(config))
        #expect(restored == config)
        #expect(restored.group(for: .front).name == "我的入口")
    }

    @Test func oldConfigKeepsAppearanceAndLoadsNewDefaults() throws {
        var config = CubeConfiguration()
        config.scale = 0.65
        config.windowPosition = WindowPosition(x: 400, y: 300)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        json.removeValue(forKey: "themeCycle")
        json.removeValue(forKey: "hover")
        let restored = try JSONDecoder().decode(CubeConfiguration.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.themeCycle.isEnabled == false)
        #expect(restored.hover.isEnabled)
        #expect(restored.hover.multiplier == 4.0)
        #expect(restored.scale == 0.65)
        #expect(restored.windowPosition == WindowPosition(x: 400, y: 300))
        #expect(restored.appearance == config.appearance)
    }

    @Test func invalidCyclesAndHoverSettingsAreRejected() throws {
        for cycle in [
            CubeThemeCycle(isEnabled: true, themes: [.ocean], intervalSeconds: 10),
            CubeThemeCycle(isEnabled: true, themes: [.ocean, .ocean], intervalSeconds: 10),
            CubeThemeCycle(isEnabled: true, themes: [.ocean, .sunset], intervalSeconds: 5)
        ] {
            var config = CubeConfiguration()
            config.themeCycle = cycle
            #expect(throws: ConfigurationError.invalidThemeCycle) { try config.validate() }
        }
        for multiplier in [0.8, 4.5, Double.nan] {
            var config = CubeConfiguration()
            config.hover = CubeHoverSettings(isEnabled: true, multiplier: multiplier)
            #expect(throws: ConfigurationError.invalidHover) { try config.validate() }
        }
    }

    @Test func everyPresetPreservesTheConfiguredGlow() throws {
        for preset in CubeThemePreset.allCases {
            let appearance = preset.appearance(glowIntensity: 0.37)
            try appearance.validate()
            #expect(appearance.glowIntensity == 0.37)
        }
    }
}
