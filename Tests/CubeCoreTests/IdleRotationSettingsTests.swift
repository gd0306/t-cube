import Foundation
import Testing
@testable import CubeCore

struct IdleRotationSettingsTests {
    @Test func oldConfigurationEnablesIdleRotationWithoutChangingShortcuts() throws {
        var config = CubeConfiguration()
        try config.rename(.front, to: "My apps")
        config.scale = 0.8
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        json.removeValue(forKey: "autoRotatesWhenIdle")
        let restored = try JSONDecoder().decode(CubeConfiguration.self, from: JSONSerialization.data(withJSONObject: json))
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as? [String: Any])
        #expect(encoded["autoRotatesWhenIdle"] as? Bool == true)
        #expect(restored.groups == config.groups)
        #expect(restored.scale == 0.8)
    }

    @Test func disabledRotationSurvivesSavingAndReloading() throws {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(CubeConfiguration())) as? [String: Any])
        json["autoRotatesWhenIdle"] = false
        let restored = try JSONDecoder().decode(CubeConfiguration.self, from: JSONSerialization.data(withJSONObject: json))
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as? [String: Any])
        #expect(encoded["autoRotatesWhenIdle"] as? Bool == false)
    }
}
