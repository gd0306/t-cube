import Foundation
import CubeCore
import ServiceManagement
import Testing
@testable import TCube

@MainActor
struct LoginItemStartupTests {
    @Test func firstInstalledStartEnablesLoginOnlyOnce() throws {
        try withDefaults { defaults in
            let service = LoginItemServiceSpy()
            let controller = makeController(service: service, defaults: defaults)
            defer { controller.stop() }

            controller.start()
            controller.start()

            #expect(service.registerCount == 1)
            #expect(controller.loginStatus == .enabled)
            #expect(controller.loginEnabled)
            #expect(controller.loginError == nil)
        }
    }

    @Test func explicitDisableSurvivesApplicationRestart() throws {
        try withDefaults { defaults in
            let service = LoginItemServiceSpy()
            let first = makeController(service: service, defaults: defaults)
            first.start()
            first.setLoginEnabled(false)
            first.stop()

            let restarted = makeController(service: service, defaults: defaults)
            defer { restarted.stop() }
            restarted.start()

            #expect(service.registerCount == 1)
            #expect(service.unregisterCount == 1)
            #expect(restarted.loginStatus == .notRegistered)
            #expect(!restarted.loginEnabled)
        }
    }

    @Test func disablingBeforeFirstStartAlsoPreservesTheChoice() throws {
        try withDefaults { defaults in
            let service = LoginItemServiceSpy(status: .enabled)
            let first = makeController(service: service, defaults: defaults)
            first.setLoginEnabled(false)
            let restarted = makeController(service: service, defaults: defaults)
            defer { restarted.stop() }

            restarted.start()

            #expect(service.registerCount == 0)
            #expect(restarted.loginStatus == .notRegistered)
        }
    }

    @Test func existingRegistrationIsPreservedWithoutReregistering() throws {
        for initialStatus in [SMAppService.Status.enabled, .requiresApproval] {
            try withDefaults { defaults in
                let service = LoginItemServiceSpy(status: initialStatus)
                let first = makeController(service: service, defaults: defaults)
                first.start()
                first.stop()
                service.status = .notRegistered
                let restarted = makeController(service: service, defaults: defaults)
                defer { restarted.stop() }

                restarted.start()

                #expect(service.registerCount == 0)
                #expect(restarted.loginStatus == .notRegistered)
                #expect(!restarted.loginEnabled)
            }
        }
    }

    @Test func defaultRegistrationFailureKeepsActualStatusAndDoesNotRetry() throws {
        try withDefaults { defaults in
            let service = LoginItemServiceSpy()
            service.registrationError = LoginItemTestError.denied
            let first = makeController(service: service, defaults: defaults)
            first.start()
            #expect(first.loginStatus == .notRegistered)
            #expect(!first.loginEnabled)
            #expect(first.loginError?.contains("test registration denied") == true)
            first.stop()
            let restarted = makeController(service: service, defaults: defaults)
            defer { restarted.stop() }

            restarted.start()

            #expect(service.registerCount == 1)
            #expect(restarted.loginStatus == .notRegistered)
        }
    }

    @Test func defaultRegistrationShowsApprovalStatusWithoutRetrying() throws {
        try withDefaults { defaults in
            let service = LoginItemServiceSpy()
            service.statusAfterRegistration = .requiresApproval
            let controller = makeController(service: service, defaults: defaults)
            defer { controller.stop() }

            controller.start()
            controller.start()

            #expect(service.registerCount == 1)
            #expect(controller.loginStatus == .requiresApproval)
            #expect(controller.loginStatusDescription.contains("等待系统批准"))
            #expect(controller.loginError == nil)
        }
    }

    @Test func explicitEnableRemainsAvailableAfterADefaultFailure() throws {
        try withDefaults { defaults in
            let service = LoginItemServiceSpy()
            service.registrationError = LoginItemTestError.denied
            let controller = makeController(service: service, defaults: defaults)
            defer { controller.stop() }
            controller.start()
            service.registrationError = nil

            controller.setLoginEnabled(true)

            #expect(service.registerCount == 2)
            #expect(controller.loginStatus == .enabled)
            #expect(controller.loginError == nil)
        }
    }

    @Test func systemDisablingAnExplicitlyEnabledItemIsNotOverriddenAtRestart() throws {
        try withDefaults { defaults in
            let service = LoginItemServiceSpy()
            let first = makeController(service: service, defaults: defaults)
            first.setLoginEnabled(true)
            service.status = .requiresApproval
            first.refreshLoginStatus()
            #expect(first.loginStatus == .requiresApproval)
            first.stop()
            service.status = .notRegistered
            let restarted = makeController(service: service, defaults: defaults)
            defer { restarted.stop() }

            restarted.start()

            #expect(service.registerCount == 1)
            #expect(restarted.loginStatus == .notRegistered)
        }
    }

    @Test func failedDisableShowsActualStateAndStillPreventsDefaultRegistration() throws {
        try withDefaults { defaults in
            let service = LoginItemServiceSpy(status: .enabled)
            service.unregistrationError = LoginItemTestError.denied
            let first = makeController(service: service, defaults: defaults)
            first.setLoginEnabled(false)
            #expect(first.loginStatus == .enabled)
            #expect(first.loginError != nil)
            service.status = .notRegistered
            let restarted = makeController(service: service, defaults: defaults)
            defer { restarted.stop() }

            restarted.start()

            #expect(service.registerCount == 0)
        }
    }

    @Test func firstInstalledStartAttemptsRegistrationWhenTheSystemHasNoRecord() throws {
        try withDefaults { defaults in
            let service = LoginItemServiceSpy(status: .notFound)
            let controller = makeController(service: service, defaults: defaults)
            defer { controller.stop() }

            controller.start()

            #expect(service.registerCount == 1)
            #expect(controller.loginStatus == .enabled)
        }
    }

    @Test func sourceAndTestBundlesCannotChangeLoginItemsOrConsumeTheDefault() throws {
        try withDefaults { defaults in
            let service = LoginItemServiceSpy()
            let source = makeController(service: service, defaults: defaults, isInstalledApplication: false)
            source.start()
            source.setLoginEnabled(true)
            source.setLoginEnabled(false)
            source.stop()
            #expect(service.registerCount == 0)
            #expect(service.unregisterCount == 0)
            #expect(source.loginError != nil)
            let installed = makeController(service: service, defaults: defaults)
            defer { installed.stop() }

            installed.start()

            #expect(service.registerCount == 1)
        }
    }

    @Test func onlyTheInstalledApplicationBundleIsEligibleForRegistration() {
        #expect(LoginItemStartupPolicy.isInstalledApplication(
            bundleURL: URL(fileURLWithPath: "/Applications/T-Cube.app"),
            bundleIdentifier: "local.tcube.launcher",
            executableURL: URL(fileURLWithPath: "/Applications/T-Cube.app/Contents/MacOS/TCube")))
        #expect(!LoginItemStartupPolicy.isInstalledApplication(
            bundleURL: URL(fileURLWithPath: "/tmp/T-Cube.app"),
            bundleIdentifier: "local.tcube.launcher",
            executableURL: URL(fileURLWithPath: "/tmp/T-Cube.app/Contents/MacOS/TCube")))
        #expect(!LoginItemStartupPolicy.isInstalledApplication(
            bundleURL: URL(fileURLWithPath: "/Applications/T-Cube.app"),
            bundleIdentifier: "local.tcube.launcher",
            executableURL: URL(fileURLWithPath: "/tmp/TCubeTests.xctest/Contents/MacOS/TCubeTests")))
        #expect(!LoginItemStartupPolicy.isInstalledApplication(
            bundleURL: Bundle.main.bundleURL,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            executableURL: Bundle.main.executableURL))
    }

    private func makeController(service: LoginItemServiceSpy, defaults: UserDefaults,
                                isInstalledApplication: Bool = true) -> LifecycleController {
        let reminder = ReleaseReminderModel(currentVersion: "0.22.5", store: ReminderMemoryStore(),
            fetch: { throw ReleaseNoticeError.unavailable })
        return LifecycleController(reminder: reminder, loginService: service, loginDefaults: defaults,
            isInstalledApplication: isInstalledApplication)
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "TCubeLoginItemTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}

@MainActor
private final class LoginItemServiceSpy: LoginItemServicing {
    var status: SMAppService.Status
    var statusAfterRegistration: SMAppService.Status = .enabled
    var registerCount = 0
    var unregisterCount = 0
    var registrationError: (any Error)?
    var unregistrationError: (any Error)?

    init(status: SMAppService.Status = .notRegistered) { self.status = status }

    func register() throws {
        registerCount += 1
        if let registrationError { throw registrationError }
        status = statusAfterRegistration
    }

    func unregister() throws {
        unregisterCount += 1
        if let unregistrationError { throw unregistrationError }
        status = .notRegistered
    }
}

private enum LoginItemTestError: LocalizedError {
    case denied
    var errorDescription: String? { "test registration denied" }
}
