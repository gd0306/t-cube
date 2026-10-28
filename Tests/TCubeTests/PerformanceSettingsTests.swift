import Foundation
import Testing
@testable import TCube

@MainActor
struct PerformanceSettingsTests {
    @Test func officeDefaultSavesPowerAndExplicitChoiceSurvivesRelaunch() throws {
        let suite = "TCubePerformanceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PerformanceSettings(defaults: defaults)
        #expect(preferences.idlePowerSavingEnabled)
        var changed: Bool?
        preferences.onChange = { changed = $0 }
        preferences.setIdlePowerSaving(false)
        #expect(changed == false)
        #expect(!PerformanceSettings(defaults: defaults).idlePowerSavingEnabled)
    }
}
