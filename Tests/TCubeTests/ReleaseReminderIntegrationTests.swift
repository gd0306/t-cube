import Testing
import CubeCore
@testable import TCube

@MainActor
struct ReleaseReminderIntegrationTests {
    @Test func unsignedBuildCanCheckForReleaseNoticesWithoutStartingAnInstaller() {
        let store = ReminderMemoryStore()
        let reminder = ReleaseReminderModel(currentVersion: "0.18.1", store: store,
            fetch: { throw ReleaseNoticeError.unavailable })
        let controller = LifecycleController(reminder: reminder)
        defer { controller.stop() }
        #expect(controller.canCheckForUpdates)
        #expect(!controller.automaticallyChecksForUpdates)
        #expect(!controller.updatesAvailable)
    }
}
