import Foundation
import Testing
import simd
@testable import CubeCore

struct DirectIconPickingTests {
    @Test func raysHitTheFourPaintedFrontIcons() {
        let cases: [(SIMD3<Float>, Int)] = [
            ([-0.18785156, 0.14273438, 3], 0), ([0.18785156, 0.14273438, 3], 1),
            ([-0.18785156, -0.16078125, 3], 2), ([0.18785156, -0.16078125, 3], 3)
        ]
        for (origin, slot) in cases {
            let hit = CubeFacePicking.icon(origin: origin, direction: [0, 0, -1])
            #expect(hit?.face == .front)
            #expect(hit?.slot == slot)
        }
    }

    @Test func iconMappingFollowsAllSixFaceOrientations() {
        for face in CubeFace.allCases {
            let point = face.orientation.act(SIMD3<Float>(-0.18785156, 0.14273438, 0.501))
            let hit = CubeFacePicking.icon(origin: point + face.normal * 3, direction: -face.normal)
            #expect(hit?.face == face)
            #expect(hit?.slot == 0)
        }
    }

    @Test func clearMarginsGapsAndInvalidRaysNeverSelectAnIcon() {
        for origin: SIMD3<Float> in [[0, 0, 3], [-0.31, 0.14273438, 3], [0.48, 0.48, 3], [1, 0, 3]] {
            #expect(CubeFacePicking.icon(origin: origin, direction: [0, 0, -1]) == nil)
        }
        #expect(CubeFacePicking.icon(origin: [0, 0, 3], direction: .zero) == nil)
        #expect(CubeFacePicking.icon(origin: [.nan, 0, 3], direction: [0, 0, -1]) == nil)
    }

    @Test func oldConfigurationKeepsFaceExpansionEnabled() throws {
        let config = CubeConfiguration()
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        json.removeValue(forKey: "expandsFacesOnClick")
        let restored = try JSONDecoder().decode(CubeConfiguration.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.expandsFacesOnClick)
        #expect(restored.groups == config.groups)
    }

    @Test func directModePersistsWithoutChangingAppearanceOrEntries() throws {
        var config = CubeConfiguration()
        config.expandsFacesOnClick = false
        config.appearance = CubeThemePreset.prism.appearance(glowIntensity: 0.65)
        try config.add(LauncherItem(url: URL(fileURLWithPath: "/Applications"), name: "应用程序", kind: .folder), to: .front)
        let restored = try JSONDecoder().decode(CubeConfiguration.self, from: JSONEncoder().encode(config))
        #expect(!restored.expandsFacesOnClick)
        #expect(restored == config)
    }
}
