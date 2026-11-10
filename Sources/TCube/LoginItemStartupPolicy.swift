import Foundation
import ServiceManagement

@MainActor
protocol LoginItemServicing {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemServicing {}

@MainActor
struct LoginItemStartupPolicy {
    private let defaults: UserDefaults
    private let initializedKey = "TCubeLoginItemDefaultEvaluatedV1"
    private let preferenceKey = "TCubeLoginItemUserPreferenceV1"

    init(defaults: UserDefaults) { self.defaults = defaults }

    func shouldEnableByDefault(status: SMAppService.Status) -> Bool {
        guard defaults.object(forKey: preferenceKey) == nil,
              !defaults.bool(forKey: initializedKey) else { return false }
        // Persist before touching Service Management so failure or revoked approval
        // never turns application startup into a registration retry loop.
        defaults.set(true, forKey: initializedKey)
        // A newly installed main app may have no BTM record yet. Registration creates it.
        return status == .notRegistered || status == .notFound
    }

    func recordExplicitPreference(_ enabled: Bool) {
        defaults.set(enabled, forKey: preferenceKey)
        defaults.set(true, forKey: initializedKey)
    }

    static func isInstalledApplication(bundleURL: URL, bundleIdentifier: String?, executableURL: URL?) -> Bool {
        bundleIdentifier == "local.tcube.launcher"
            && bundleURL.standardizedFileURL.path == "/Applications/T-Cube.app"
            && executableURL?.standardizedFileURL.path == "/Applications/T-Cube.app/Contents/MacOS/TCube"
    }
}
