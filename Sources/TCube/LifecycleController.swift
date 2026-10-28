import AppKit
import Combine
import ServiceManagement
import Sparkle

@MainActor
final class LifecycleController: NSObject, ObservableObject {
    @Published private(set) var loginStatus: SMAppService.Status = .notRegistered
    @Published private(set) var loginError: String?
    @Published private(set) var updateIssue: String?
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false

    private var updaterController: SPUStandardUpdaterController?
    private var activationObserver: NSObjectProtocol?
    private let loginService = SMAppService.mainApp

    var loginEnabled: Bool { loginStatus == .enabled || loginStatus == .requiresApproval }
    var updatesAvailable: Bool { updaterController != nil && updateIssue == nil }

    var loginStatusDescription: String {
        switch loginStatus {
        case .enabled: "已启用，登录后自动启动。"
        case .requiresApproval: "等待系统批准，请在系统设置的登录项中允许 T-Cube。"
        case .notRegistered: "尚未启用登录时启动。"
        case .notFound: "系统尚未识别此登录项，可尝试开启；若失败，请重新打开应用或检查系统登录项设置。"
        @unknown default: "无法读取登录项状态，请在系统设置中检查。"
        }
    }

    func start() {
        refreshLoginStatus()
        if activationObserver == nil {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshLoginStatus() }
            }
        }
        guard updaterController == nil else { return }
        let configuration = UpdateConfiguration(
            feedURL: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            publicKey: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        )
        updateIssue = configuration.issue
        guard updateIssue == nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
        )
        do {
            try controller.updater.start()
            updaterController = controller
            controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
            controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecksForUpdates)
        } catch {
            updateIssue = "无法启动更新检查：\(error.localizedDescription)"
        }
    }

    func refreshLoginStatus() {
        loginStatus = loginService.status
    }

    func setLoginEnabled(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled {
                try loginService.register()
            } else {
                try loginService.unregister()
            }
        } catch {
            loginError = "无法更改登录项：\(error.localizedDescription)"
        }
        refreshLoginStatus()
    }

    func openLoginSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updaterController?.updater.automaticallyChecksForUpdates = enabled
    }

    func checkForUpdates() {
        guard let updaterController, canCheckForUpdates else {
            if updateIssue != nil { openReleases() }
            return
        }
        updaterController.checkForUpdates(nil)
    }

    func openReleases() {
        NSWorkspace.shared.open(URL(string: "https://github.com/gd0306/t-cube/releases")!)
    }
}
