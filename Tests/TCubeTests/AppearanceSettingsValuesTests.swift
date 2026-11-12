import Foundation
import CubeCore
import Testing
@testable import TCube

@MainActor
struct AppearanceSettingsValuesTests {
    @Test func restoringAppearanceDefaultsPreservesLaunchersAndPosition() throws {
        var configuration = CubeConfiguration()
        try configuration.rename(.front, to: "我的入口")
        configuration.windowPosition = WindowPosition(x: 120, y: 240)
        configuration.appearance.material = .slime
        configuration.scale = 1.4
        configuration.themeCycle.isEnabled = true
        let groups = configuration.groups
        let position = configuration.windowPosition
        let defaults = CubeConfiguration()
        AppearanceSettingsValues(configuration: defaults).apply(to: &configuration)
        #expect(configuration.groups == groups)
        #expect(configuration.windowPosition == position)
        #expect(AppearanceSettingsValues(configuration: configuration) == AppearanceSettingsValues(configuration: defaults))
        try configuration.validate()
    }

    @Test func appearanceChangePersistsWithoutChangingOtherConfiguration() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ConfigurationStore(url: folder.appendingPathComponent("configuration.json"))
        let model = AppModel(store: store)
        let originalGroups = model.configuration.groups
        var values = AppearanceSettingsValues(configuration: model.configuration)
        values.appearance.material = .slime
        values.hover.multiplier = 2.5
        model.change { values.apply(to: &$0) }
        let saved = try store.load()
        #expect(saved.appearance.material == .slime)
        #expect(saved.hover.multiplier == 2.5)
        #expect(saved.groups == originalGroups)
    }
}
