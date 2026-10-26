import AppKit
import CubeCore
import Testing
@testable import TCube

@MainActor
struct ThemeCycleRuntimeTests {
    @Test func cyclingNewMaterialsRestoresTheManualMaterialWhenDisabled() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        var configuration = CubeConfiguration()
        configuration.appearance = CubeAppearance(primaryHex: "#123456", secondaryHex: "#ABCDEF", glowIntensity: 0.37, surfaceStyle: .moonstone)
        configuration.themeCycle = CubeThemeCycle(isEnabled: true, themes: [.prism, .auroraFlow])
        try store.save(configuration)
        let model = AppModel(store: store)
        defer { model.stopThemeCycle() }
        #expect(model.displayedAppearance.surfaceStyle == .iridescent)
        model.advanceTheme()
        #expect(model.displayedAppearance.surfaceStyle == .aurora)
        #expect(model.displayedAppearance.glowIntensity == 0.37)
        #expect(try store.load() == configuration)
        model.change { $0.themeCycle.isEnabled = false }
        #expect(model.displayedAppearance == configuration.appearance)
        #expect(try store.load().appearance.surfaceStyle == .moonstone)
    }

    @Test func configuredOrderWrapsAndPreservesManualGlow() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        var configuration = CubeConfiguration()
        configuration.appearance.glowIntensity = 0.37
        configuration.themeCycle = CubeThemeCycle(isEnabled: true, themes: [.forest, .sunset, .ocean])
        try store.save(configuration)
        let model = AppModel(store: store)
        defer { model.stopThemeCycle() }

        #expect(model.activeTheme == .forest)
        #expect(model.displayedAppearance.primaryHex == "#70E5AB")
        #expect(model.displayedAppearance.glowIntensity == 0.37)
        model.advanceTheme()
        #expect(model.activeTheme == .sunset)
        #expect(model.displayedAppearance.secondaryHex == "#EE79B5")
        model.advanceTheme()
        #expect(model.activeTheme == .ocean)
        model.advanceTheme()
        #expect(model.activeTheme == .forest)
        #expect(model.configuration == configuration)
    }

    @Test func tickUpdatesAppearanceWithoutWritingOrRebuilding() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        var configuration = CubeConfiguration()
        configuration.themeCycle.isEnabled = true
        try store.save(configuration)
        let saved = try Data(contentsOf: store.url)
        let savedAttributes = try FileManager.default.attributesOfItem(atPath: store.url.path)
        let model = AppModel(store: store)
        defer { model.stopThemeCycle() }
        var appearanceUpdates = 0
        var configurationUpdates = 0
        model.onAppearanceChange = { appearanceUpdates += 1 }
        model.onChange = { configurationUpdates += 1 }

        model.advanceTheme()

        #expect(appearanceUpdates == 1)
        #expect(configurationUpdates == 0)
        #expect(try Data(contentsOf: store.url) == saved)
        let currentAttributes = try FileManager.default.attributesOfItem(atPath: store.url.path)
        #expect(currentAttributes[.modificationDate] as? Date == savedAttributes[.modificationDate] as? Date)
        #expect(currentAttributes[.systemFileNumber] as? UInt64 == savedAttributes[.systemFileNumber] as? UInt64)
    }

    @Test func disablingCycleRestoresManualColorsAndStopsAdvancement() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        var configuration = CubeConfiguration()
        configuration.appearance = CubeAppearance(primaryHex: "#123456", secondaryHex: "#FEDCBA", glowIntensity: 0.71)
        configuration.themeCycle.isEnabled = true
        try store.save(configuration)
        let model = AppModel(store: store)
        defer { model.stopThemeCycle() }
        model.advanceTheme()

        model.change { $0.themeCycle.isEnabled = false }

        #expect(model.activeTheme == nil)
        #expect(model.displayedAppearance == configuration.appearance)
        model.advanceTheme()
        #expect(model.displayedAppearance == configuration.appearance)
        #expect(try store.load().appearance == configuration.appearance)
    }

    @Test func positionAndEntryChangesKeepCurrentThemeWhileCycleChangesRestartIt() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        var configuration = CubeConfiguration()
        configuration.themeCycle.isEnabled = true
        try store.save(configuration)
        let model = AppModel(store: store)
        defer { model.stopThemeCycle() }
        model.advanceTheme()
        #expect(model.activeTheme == .ocean)

        model.savePosition(NSPoint(x: 120, y: 240))
        model.change { try $0.rename(.front, to: "工作") }
        model.change { $0.appearance.glowIntensity = 0.25 }

        #expect(model.activeTheme == .ocean)
        #expect(model.displayedAppearance.glowIntensity == 0.25)
        #expect(try store.load().group(for: .front).name == "工作")
        model.change { $0.themeCycle = CubeThemeCycle(isEnabled: true, themes: [.blossom, .forest], intervalSeconds: 20) }
        #expect(model.activeTheme == .blossom)
        model.advanceTheme()
        #expect(model.activeTheme == .forest)
    }

    @Test func sleepingCycleDoesNotRetainItsModel() async throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        var configuration = CubeConfiguration()
        configuration.themeCycle.isEnabled = true
        try store.save(configuration)
        var model: AppModel? = AppModel(store: store)
        weak var releasedModel: AppModel?
        releasedModel = model
        await Task.yield()
        model = nil
        #expect(releasedModel == nil)
    }

    private func temporaryStore() -> ConfigurationStore {
        ConfigurationStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("TCube-theme-runtime-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("configuration.json"))
    }
}
