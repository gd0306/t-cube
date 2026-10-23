import Foundation
import Testing
@testable import CubeCore

struct AppearanceSettingsTests {
    @Test func appearanceColorsAndGlowSurviveDiskRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(url: directory.appendingPathComponent("settings.json"))
        var configuration = CubeConfiguration()
        configuration.appearance = CubeAppearance(primaryHex: "#4CB8FF", secondaryHex: "#3EE4CF", glowIntensity: 0.7)
        try store.save(configuration)
        let restored = try store.load()
        #expect(restored.appearance.primaryHex == "#4CB8FF")
        #expect(restored.appearance.secondaryHex == "#3EE4CF")
        #expect(restored.appearance.glowIntensity == 0.7)
    }

    @Test func previousVersionWithoutAppearanceKeepsItsGroupsAndLoadsDefaults() throws {
        var configuration = CubeConfiguration()
        try configuration.rename(.front, to: "我的应用")
        let data = try JSONEncoder().encode(configuration)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "appearance")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        let restored = try JSONDecoder().decode(CubeConfiguration.self, from: legacy)
        #expect(restored.group(for: .front).name == "我的应用")
        #expect(restored.appearance == CubeAppearance())
    }

    @Test func invalidAppearanceDoesNotReplaceSavedConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(url: directory.appendingPathComponent("settings.json"))
        try store.save(CubeConfiguration())
        let original = try Data(contentsOf: store.url)
        for appearance in [CubeAppearance(primaryHex: "#BAD"), CubeAppearance(glowIntensity: 1.1), CubeAppearance(glowIntensity: .nan)] {
            var invalid = CubeConfiguration()
            invalid.appearance = appearance
            #expect(throws: ConfigurationError.invalidAppearance) { try store.save(invalid) }
            #expect(try Data(contentsOf: store.url) == original)
        }
    }
}
