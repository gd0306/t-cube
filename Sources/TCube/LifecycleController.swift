import AppKit
import Combine
import CubeCore
import ServiceManagement
import OSLog
import Sparkle

@MainActor
final class LifecycleController: NSObject, ObservableObject {
    @Published private(set) var loginStatus: SMAppService.Status = .notRegistered
    @Published private(set) var loginError: String?
    @Published private(set) var updateIssue: String?
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false

    let reminder: ReleaseReminderModel
    private var reminderObserver: AnyCancellable?

    init(reminder: ReleaseReminderModel? = nil,
         loginService: (any LoginItemServicing)? = nil,
         loginDefaults: UserDefaults = .standard,
         isInstalledApplication: Bool? = nil) {
        self.loginService = loginService ?? SMAppService.mainApp
        self.loginStartupPolicy = LoginItemStartupPolicy(defaults: loginDefaults)
        self.isInstalledApplication = isInstalledApplication ?? LoginItemStartupPolicy.isInstalledApplication(
            bundleURL: Bundle.main.bundleURL, bundleIdentifier: Bundle.main.bundleIdentifier,
            executableURL: Bundle.main.executableURL)
        if let reminder { self.reminder = reminder }
        else {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
            let client = ReleaseNoticeClient(version: version)
            self.reminder = ReleaseReminderModel(currentVersion: version, store: UserDefaultsReleaseReminderStore(),
                fetch: { try await client.fetch() }, notify: { notice in
                    Self.presentRelease(notice)
                    return true
                })
        }
        super.init()
        reminderObserver = Publishers.CombineLatest3(self.reminder.$enabled, self.reminder.$isChecking, self.reminder.$preferencesHealthy)
            .sink { [weak self] enabled, checking, healthy in
                guard let self, self.updaterController == nil else { return }
                self.automaticallyChecksForUpdates = enabled
                self.canCheckForUpdates = healthy && !checking
            }
    }

    private var updaterController: SPUStandardUpdaterController?
    private var activationObserver: NSObjectProtocol?
    private let loginService: any LoginItemServicing
    private let loginStartupPolicy: LoginItemStartupPolicy
    private let isInstalledApplication: Bool

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
        if isInstalledApplication, loginStartupPolicy.shouldEnableByDefault(status: loginStatus) {
            updateLoginRegistration(true)
        }
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
        guard updateIssue == nil else { reminder.start(); return }
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
            reminder.start()
        }
    }

    func refreshLoginStatus() {
        loginStatus = loginService.status
        if isInstalledApplication {
            Logger(subsystem: "local.tcube.launcher", category: "LoginStartup")
                .notice("Login item status: \(self.loginStatus.rawValue)")
        }
    }

    func setLoginEnabled(_ enabled: Bool) {
        guard isInstalledApplication else {
            loginError = "请先将 T-Cube 安装到 /Applications 后再更改登录项。"
            refreshLoginStatus()
            return
        }
        loginStartupPolicy.recordExplicitPreference(enabled)
        updateLoginRegistration(enabled)
    }

    private func updateLoginRegistration(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled {
                try loginService.register()
            } else {
                try loginService.unregister()
            }
        } catch {
            loginError = "无法更改登录项：\(error.localizedDescription)"
            Logger(subsystem: "local.tcube.launcher", category: "LoginStartup")
                .error("Login item registration failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshLoginStatus()
    }

    func openLoginSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        if let updaterController { updaterController.updater.automaticallyChecksForUpdates = enabled }
        else { reminder.setEnabled(enabled) }
    }

    func checkForUpdates() {
        guard let updaterController, canCheckForUpdates else {
            guard canCheckForUpdates else { return }
            Task { [weak self] in
                guard let self else { return }
                let result = await self.reminder.check(manual: true)
                if case .ignored = result { return }
                if case .available(let notice) = result { Self.presentRelease(notice) }
                else {
                    let alert = NSAlert()
                    alert.messageText = "版本检查"
                    alert.informativeText = self.reminder.status
                    alert.addButton(withTitle: "好")
                    NSApp.activate(ignoringOtherApps: true)
                    alert.runModal()
                }
            }
            return
        }
        updaterController.checkForUpdates(nil)
    }

    func stop() {
        reminder.stop()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
    }

    private static func presentRelease(_ notice: ReleaseNotice) {
        let alert = NSAlert()
        alert.messageText = "T-Cube 有新版本 \(notice.version)"
        alert.informativeText = "可前往 GitHub 发布页面查看说明，手动下载安装。"
        alert.addButton(withTitle: "查看发布页")
        alert.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(notice.pageURL) }
    }

    func openReleases() {
        NSWorkspace.shared.open(URL(string: "https://github.com/gd0306/t-cube/releases")!)
    }
}
