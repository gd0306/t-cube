import Combine
import CubeCore
import Foundation

struct ReleaseReminderPreferences: Codable, Equatable {
    var version = 1
    var enabled = false
    var lastAttempt: Date?
    var retryUntil: Date?
    var highestNotifiedVersion: String?
}

@MainActor
protocol ReleaseReminderStoring {
    func load() throws -> ReleaseReminderPreferences
    func save(_ preferences: ReleaseReminderPreferences) throws
}

@MainActor
final class UserDefaultsReleaseReminderStore: ReleaseReminderStoring {
    private let defaults: UserDefaults
    private let key = "TCubeReleaseReminderPreferencesV1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() throws -> ReleaseReminderPreferences {
        guard let value = defaults.object(forKey: key) else { return ReleaseReminderPreferences() }
        guard let data = value as? Data, data.count <= 16_384 else { throw CocoaError(.fileReadCorruptFile) }
        let result = try JSONDecoder().decode(ReleaseReminderPreferences.self, from: data)
        guard result.version == 1,
              result.highestNotifiedVersion.map({ ReleaseVersion($0) != nil }) ?? true else { throw CocoaError(.fileReadCorruptFile) }
        return result
    }
    func save(_ preferences: ReleaseReminderPreferences) throws {
        defaults.set(try JSONEncoder().encode(preferences), forKey: key)
    }
}

enum ReleaseReminderCheckResult: Equatable, Sendable {
    case ignored
    case status
    case available(ReleaseNotice)
}

@MainActor
final class ReleaseReminderModel: ObservableObject {
    typealias Schedule = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> AnyCancellable
    static let interval: TimeInterval = 6 * 60 * 60
    static let manualCooldown: TimeInterval = 60
    @Published private(set) var enabled = false
    @Published private(set) var isChecking = false
    @Published private(set) var availableRelease: ReleaseNotice?
    @Published private(set) var status = "自动检查默认关闭，可手动检查新版本。"
    @Published private(set) var preferencesHealthy = true
    var lastChecked: Date? { preferences.lastAttempt }
    let currentVersion: ReleaseVersion
    private let store: any ReleaseReminderStoring
    private let fetch: @Sendable () async throws -> ReleaseNotice
    private let clock: @MainActor () -> Date
    private let schedule: Schedule
    private let notify: @MainActor (ReleaseNotice) async -> Bool
    private var preferences = ReleaseReminderPreferences()
    private var timer: AnyCancellable?
    private var request: Task<ReleaseNotice, any Error>?
    private var generation = 0
    private var started = false
    private var stopped = false

    init(currentVersion: String, store: any ReleaseReminderStoring,
         fetch: @escaping @Sendable () async throws -> ReleaseNotice,
         clock: @escaping @MainActor () -> Date = Date.init,
         schedule: @escaping Schedule = ReleaseReminderModel.scheduleTimer,
         notify: @escaping @MainActor (ReleaseNotice) async -> Bool = { _ in false }) {
        self.currentVersion = ReleaseVersion(currentVersion) ?? ReleaseVersion("0.0.0")!
        self.store = store; self.fetch = fetch; self.clock = clock; self.schedule = schedule; self.notify = notify
        do {
            preferences = try store.load(); enabled = preferences.enabled
            if enabled { status = "已开启版本提醒，每 6 小时检查一次。" }
        }
        catch { blockPreferences() }
    }

    func start() {
        guard !started else { return }
        started = true
        scheduleNext()
    }

    func stop() {
        stopped = true; generation += 1
        timer?.cancel(); timer = nil; request?.cancel()
    }

    func setEnabled(_ value: Bool) {
        guard preferencesHealthy, !stopped, value != enabled else { return }
        var next = preferences; next.enabled = value
        guard persist(next) else { return }
        enabled = value; generation += 1
        request?.cancel()
        status = value ? "已开启版本提醒，每 6 小时检查一次。" : "自动检查已关闭，仍可手动检查。"
        scheduleNext()
    }

    /// Only a fresh successful response produces an available-version dialog.
    @discardableResult
    func check(manual: Bool) async -> ReleaseReminderCheckResult {
        guard !stopped, preferencesHealthy, !isChecking, manual || enabled else { return .ignored }
        let now = clock()
        let spacing = manual ? Self.manualCooldown : Self.interval
        let remaining = preferences.lastAttempt.map { $0 > now ? 0 : max(0, spacing - now.timeIntervalSince($0)) } ?? 0
        let retry = preferences.retryUntil.map { max(0, min(86_400, $0.timeIntervalSince(now))) } ?? 0
        guard remaining == 0, retry == 0 else {
            if manual { status = retry > 0 ? "GitHub 暂时限制检查频率，请稍后重试。" : "刚刚已检查过，请至少间隔 1 分钟再试。" }
            scheduleNext(); return manual ? .status : .ignored
        }
        var next = preferences; next.lastAttempt = now
        guard persist(next) else { return manual ? .status : .ignored }
        isChecking = true; status = "正在检查 GitHub 新版本…"
        timer?.cancel(); timer = nil
        let token = generation, fetch = self.fetch
        let task = Task { try await fetch() }
        request = task
        defer { request = nil; isChecking = false; scheduleNext() }
        do {
            let notice = try await task.value
            guard generation == token, !stopped, !Task.isCancelled else { return .ignored }
            var success = preferences; success.retryUntil = nil
            guard persist(success) else { return manual ? .status : .ignored }
            if notice.version > currentVersion {
                availableRelease = notice
                status = "发现新版本 \(notice.version)。可前往发布页面手动下载安装。"
                let previous = preferences.highestNotifiedVersion.flatMap(ReleaseVersion.init)
                if !manual, enabled, previous.map({ notice.version > $0 }) ?? true {
                    let shown = await notify(notice)
                    guard generation == token, !stopped, enabled else { return .ignored }
                    if shown {
                        var notified = preferences
                        notified.highestNotifiedVersion = notice.version.description
                        _ = persist(notified)
                    }
                }
                return .available(notice)
            } else {
                availableRelease = nil
                status = "当前没有更新的稳定版本。"
            }
            return .status
        } catch {
            guard generation == token, !stopped, !Task.isCancelled, !(error is CancellationError) else { return .ignored }
            if case ReleaseNoticeError.rateLimited(let until) = error {
                var limited = preferences
                limited.retryUntil = now.addingTimeInterval(max(60, min(86_400, until.timeIntervalSince(now))))
                _ = persist(limited)
                if preferencesHealthy { status = "GitHub 暂时限制检查频率，请稍后重试。" }
            } else { status = "暂时无法检查新版本，请检查网络后重试，或直接查看发布页面。" }
            return .status
        }
    }

    private func persist(_ value: ReleaseReminderPreferences) -> Bool {
        guard preferencesHealthy else { return false }
        do { try store.save(value); preferences = value; return true }
        catch { blockPreferences(); return false }
    }

    private func blockPreferences() {
        preferencesHealthy = false; enabled = false; generation += 1
        timer?.cancel(); timer = nil; request?.cancel()
        status = "版本提醒设置无法读取或保存，原设置已保留。可直接查看发布页面。"
    }

    private func scheduleNext() {
        timer?.cancel(); timer = nil
        guard started, !stopped, enabled, preferencesHealthy, !isChecking else { return }
        let now = clock()
        let delay = preferences.lastAttempt.map { $0 > now ? 0 : max(0, Self.interval - now.timeIntervalSince($0)) } ?? 0
        let retry = preferences.retryUntil.map { max(0, min(86_400, $0.timeIntervalSince(now))) } ?? 0
        timer = schedule(max(delay, retry)) { [weak self] in
            Task { [weak self] in await self?.check(manual: false) }
        }
    }

    static func scheduleTimer(delay: TimeInterval, action: @escaping @MainActor () -> Void) -> AnyCancellable {
        let timer = Timer(timeInterval: max(0.01, delay), repeats: false) { _ in MainActor.assumeIsolated { action() } }
        timer.tolerance = min(60, delay / 10)
        RunLoop.main.add(timer, forMode: .common)
        return AnyCancellable { timer.invalidate() }
    }
}
