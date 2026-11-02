import Combine
import CubeCore
import Foundation
import Testing
@testable import TCube

@MainActor
@Suite(.serialized)
struct ReleaseReminderModelTests {
    @Test func optInPersistsCheckSpacingAndOnlyIncreasingVersionsPromptOnce() async throws {
        let store = ReminderMemoryStore(), clock = ReminderClock(), timer = ReminderTimer()
        let provider = ReminderProvider(), prompts = ReminderPrompts()
        let model = make(store, clock, timer, provider, prompts)
        model.start()
        #expect(timer.delay == nil)
        #expect(await provider.calls == 0)
        model.setEnabled(true)
        #expect(timer.delay == 0)
        await model.check(manual: false)
        #expect(await provider.calls == 1 && prompts.versions == ["0.20.0"])
        #expect(store.value.highestNotifiedVersion == "0.20.0")
        #expect(timer.delay == 21_600)
        clock.now += 21_600
        await model.check(manual: false)
        #expect(prompts.versions == ["0.20.0"])
        await provider.setVersion("0.19.0")
        clock.now += 21_600
        await model.check(manual: false)
        #expect(prompts.versions == ["0.20.0"])
        await provider.setVersion("0.21.0")
        clock.now += 21_600
        await model.check(manual: false)
        #expect(prompts.versions == ["0.20.0", "0.21.0"])
        model.stop()
        let reloadedTimer = ReminderTimer()
        let reloaded = make(store, clock, reloadedTimer, provider, prompts)
        defer { reloaded.stop() }
        reloaded.start()
        #expect(reloaded.enabled && reloadedTimer.delay == 21_600)
        #expect(reloaded.status.contains("已开启"))
        #expect(await provider.calls == 4)
    }

    @Test func manualChecksAreAvailableWhenDisabledButCooldownAndRateLimitsPreventSpam() async throws {
        let store = ReminderMemoryStore(), clock = ReminderClock(), timer = ReminderTimer()
        let provider = ReminderProvider(), prompts = ReminderPrompts()
        let model = make(store, clock, timer, provider, prompts)
        defer { model.stop() }
        await model.check(manual: true)
        #expect(await provider.calls == 1 && prompts.versions.isEmpty)
        await model.check(manual: true)
        #expect(await provider.calls == 1)
        clock.now += 61
        await provider.setError(.rateLimited(until: clock.now.addingTimeInterval(120)))
        await model.check(manual: true)
        #expect(await provider.calls == 2)
        clock.now += 61
        await model.check(manual: true)
        #expect(await provider.calls == 2)
        #expect(model.status.contains("限制"))
        clock.now += 60
        await provider.setVersion("0.18.1")
        await model.check(manual: true)
        #expect(await provider.calls == 3)
        #expect(model.availableRelease == nil)
        #expect(model.status.contains("没有更新"))
    }

    @Test func disablingInvalidatesLatePayloadAndConcurrentChecksShareOneRequest() async throws {
        let store = ReminderMemoryStore(), clock = ReminderClock(), timer = ReminderTimer()
        let provider = ReminderProvider(), prompts = ReminderPrompts()
        await provider.setDelayed()
        let model = make(store, clock, timer, provider, prompts)
        model.start(); model.setEnabled(true)
        let pending = Task { await model.check(manual: false) }
        await provider.waitForRequest()
        #expect(model.isChecking)
        #expect(await model.check(manual: true) == .ignored)
        #expect(await provider.calls == 1)
        model.setEnabled(false)
        await provider.finish()
        #expect(await pending.value == .ignored)
        #expect(model.availableRelease == nil && prompts.versions.isEmpty)
        #expect(!model.enabled && timer.delay == nil)
        model.stop()
    }

    @Test func storageFailuresStopNetworkAndKeepThePreviousState() async throws {
        let store = ReminderMemoryStore(), clock = ReminderClock(), timer = ReminderTimer()
        let provider = ReminderProvider(), prompts = ReminderPrompts()
        let model = make(store, clock, timer, provider, prompts)
        store.failWrites = true
        model.start(); model.setEnabled(true)
        await model.check(manual: true)
        #expect(!model.preferencesHealthy && !model.enabled)
        #expect(await provider.calls == 0 && timer.delay == nil)
        #expect(store.value == ReleaseReminderPreferences())
        model.stop()
        store.failReads = true
        let unreadable = make(store, clock, timer, provider, prompts)
        defer { unreadable.stop() }
        unreadable.start(); await unreadable.check(manual: true)
        #expect(!unreadable.preferencesHealthy)
        #expect(await provider.calls == 0)
    }

    @Test func networkFailuresRemainErrorsAndRetryWithoutClaimingTheCurrentVersionIsLatest() async throws {
        let store = ReminderMemoryStore(), clock = ReminderClock(), timer = ReminderTimer()
        let provider = ReminderProvider(), prompts = ReminderPrompts()
        await provider.setError(.unavailable)
        let model = make(store, clock, timer, provider, prompts)
        defer { model.stop() }
        model.start(); model.setEnabled(true)
        await model.check(manual: false)
        #expect(model.status.contains("无法检查"))
        #expect(timer.delay == 21_600 && prompts.versions.isEmpty)
        clock.now += 21_600
        await provider.setVersion("0.20.0")
        await model.check(manual: false)
        #expect(model.availableRelease?.version.description == "0.20.0")
        #expect(prompts.versions == ["0.20.0"])
    }

    @Test func userDefaultsPreferenceRoundTripAndCorruptDataArePreserved() throws {
        let name = "TCubeReleaseReminderTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = UserDefaultsReleaseReminderStore(defaults: defaults)
        #expect(try store.load() == ReleaseReminderPreferences())
        var prefs = ReleaseReminderPreferences(); prefs.enabled = true
        prefs.lastAttempt = Date(timeIntervalSince1970: 1000); prefs.highestNotifiedVersion = "0.20.0"
        try store.save(prefs)
        #expect(try UserDefaultsReleaseReminderStore(defaults: defaults).load() == prefs)
        let corrupt = Data("invalid owned preference fixture".utf8)
        defaults.set(corrupt, forKey: "TCubeReleaseReminderPreferencesV1")
        #expect(throws: (any Error).self) { try store.load() }
        #expect(defaults.data(forKey: "TCubeReleaseReminderPreferencesV1") == corrupt)
    }

    @Test func clockRollbackCannotPinTheCheckerBehindAFutureAttempt() async throws {
        let store = ReminderMemoryStore(), clock = ReminderClock(), timer = ReminderTimer()
        store.value.lastAttempt = clock.now.addingTimeInterval(86_400)
        let provider = ReminderProvider(), prompts = ReminderPrompts()
        let model = make(store, clock, timer, provider, prompts)
        defer { model.stop() }
        await model.check(manual: true)
        #expect(await provider.calls == 1)
        #expect(store.value.lastAttempt == clock.now)
    }

    @Test func failedOrThrottledChecksNeverPresentCachedReleaseAsAFreshSuccess() async throws {
        let store = ReminderMemoryStore(), clock = ReminderClock(), timer = ReminderTimer()
        let provider = ReminderProvider(), prompts = ReminderPrompts()
        let model = make(store, clock, timer, provider, prompts)
        defer { model.stop() }
        if case .available(let notice) = await model.check(manual: true) { #expect(notice.version.description == "0.20.0") }
        else { Issue.record("Fresh valid metadata must expose the newer release") }
        #expect(await model.check(manual: true) == .status)
        clock.now += 61
        await provider.setError(.unavailable)
        #expect(await model.check(manual: true) == .status)
        #expect(model.availableRelease?.version.description == "0.20.0")
        #expect(model.status.contains("无法检查"))
    }

    private func make(_ store: ReminderMemoryStore, _ clock: ReminderClock, _ timer: ReminderTimer,
                      _ provider: ReminderProvider, _ prompts: ReminderPrompts) -> ReleaseReminderModel {
        ReleaseReminderModel(currentVersion: "0.18.1", store: store, fetch: { try await provider.fetch() },
            clock: { clock.now }, schedule: { delay, callback in timer.schedule(delay, callback) },
            notify: { notice in prompts.versions.append(notice.version.description); return true })
    }
}

@MainActor
final class ReminderMemoryStore: ReleaseReminderStoring {
    var value = ReleaseReminderPreferences()
    var failReads = false, failWrites = false
    func load() throws -> ReleaseReminderPreferences { if failReads { throw CocoaError(.fileReadCorruptFile) }; return value }
    func save(_ value: ReleaseReminderPreferences) throws { if failWrites { throw CocoaError(.fileWriteNoPermission) }; self.value = value }
}
@MainActor
private final class ReminderClock { var now = Date(timeIntervalSince1970: 100_000) }
@MainActor
private final class ReminderPrompts { var versions: [String] = [] }
@MainActor
private final class ReminderTimer {
    var delay: TimeInterval?
    private var token = UUID()
    func schedule(_ delay: TimeInterval, _ callback: @escaping @MainActor () -> Void) -> AnyCancellable {
        self.delay = delay; token = UUID(); let current = token
        return AnyCancellable { [weak self] in if self?.token == current { self?.delay = nil } }
    }
}
private actor ReminderProvider {
    private(set) var calls = 0
    private var version = "0.20.0"
    private var error: ReleaseNoticeError?
    private var delayed = false
    private var waiting: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?
    func setVersion(_ version: String) { self.version = version; error = nil }
    func setError(_ error: ReleaseNoticeError) { self.error = error }
    func setDelayed() { delayed = true }
    func waitForRequest() async { if calls == 0 { await withCheckedContinuation { arrival = $0 } } }
    func finish() { waiting?.resume(); waiting = nil }
    func fetch() async throws -> ReleaseNotice {
        calls += 1; arrival?.resume(); arrival = nil
        if delayed { await withCheckedContinuation { waiting = $0 } }
        if let error { throw error }
        return try ReleaseNotice.decode(JSONSerialization.data(withJSONObject: ["tag_name": "v\(version)", "draft": false,
            "prerelease": false, "html_url": "https://github.com/gd0306/t-cube/releases/tag/v\(version)"]))
    }
}
