import AppKit
import Testing
@testable import TCube

@MainActor
struct ControlHoldMonitorTests {
    private func timer(after delay: TimeInterval, fire: @escaping @MainActor () -> Void) -> Timer {
        Timer(timeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated { fire() } }
    }

    @Test func verifiedPressSchedulesItsPhysicalDeadlineAndFiresOnlyAfterOneSecond() throws {
        var sample = snapshot(at: 0, held: false, modifierCount: 0)
        var fired = 0
        var delays: [TimeInterval] = []
        var timers: [Timer] = []
        let monitor = ControlHoldMonitor(readSnapshot: { sample }, scheduleDeadline: { delay, fire in
            delays.append(delay)
            let timer = timer(after: delay, fire: fire)
            timers.append(timer)
            return timer
        }, action: { fired += 1 })
        defer { monitor.stop() }
        monitor.poll()
        sample = snapshot(at: 0.125, modifierAge: 0.0625); monitor.poll()
        #expect(delays == [0.9375])
        let deadline = try #require(timers.first)
        for tick in 2...8 { sample.time = Double(tick) / 8; monitor.poll() }
        #expect(fired == 0)
        sample.time = 1.0624; monitor.poll()
        #expect(fired == 0)
        sample.time = 1.0625; deadline.fire()
        #expect(fired == 1)
        #expect(!deadline.isValid)
        #expect(timers.count == 1)
    }

    @Test func deadlineReadsFreshInputInsteadOfUnconditionallyOpening() throws {
        for interruption in 0..<6 {
            var sample = snapshot(at: 0, held: false, modifierCount: 0)
            var fired = 0
            var timers: [Timer] = []
            let monitor = ControlHoldMonitor(readSnapshot: { sample }, scheduleDeadline: { delay, fire in
                let timer = timer(after: delay, fire: fire)
                timers.append(timer)
                return timer
            }, action: { fired += 1 })
            defer { monitor.stop() }
            monitor.poll()
            sample = snapshot(at: 0.125, modifierAge: 0.0625); monitor.poll()
            let deadline = try #require(timers.first)
            for tick in 2...8 { sample.time = Double(tick) / 8; monitor.poll() }
            sample.time = 1.0625
            switch interruption {
            case 0: sample.controlHeld = false
            case 1: sample.inputCounts[0] += 1
            case 2: sample.inputCounts[4] += 1
            case 3: sample.mouseButtonHeld = true
            case 4: sample.modifierCount += 2
            default: sample.time = 1.625 // A gap after the hold began still cancels.
            }
            deadline.fire()
            #expect(fired == 0)
            #expect(!deadline.isValid)
        }
    }

    @Test func releaseStopAndSessionTransitionsInvalidatePendingDeadlines() throws {
        let center = NotificationCenter()
        for cancellation in 0..<6 {
            var sample = snapshot(at: 0, held: false, modifierCount: 0)
            var timers: [Timer] = []
            let monitor = ControlHoldMonitor(readSnapshot: { sample }, notificationCenter: center,
                scheduleDeadline: { delay, fire in
                    let timer = timer(after: delay, fire: fire)
                    timers.append(timer)
                    return timer
                }, action: {})
            defer { monitor.stop() }
            monitor.start()
            sample = snapshot(at: 0.125, modifierAge: 0.0625); monitor.poll()
            let deadline = try #require(timers.first)
            #expect(deadline.isValid)
            switch cancellation {
            case 0: sample = snapshot(at: 0.25, held: false, modifierCount: 2); monitor.poll()
            case 1: monitor.stop()
            default:
                let names = [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                             NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification]
                center.post(name: names[cancellation - 2], object: nil)
            }
            #expect(!deadline.isValid)
        }
    }

    @Test func delayedFirstSampleSchedulesOnlyTheRemainingPhysicalHoldTime() throws {
        var sample = snapshot(at: 0, held: false, modifierCount: 0)
        var delays: [TimeInterval] = []
        var timers: [Timer] = []
        var fired = 0
        let monitor = ControlHoldMonitor(readSnapshot: { sample }, scheduleDeadline: { delay, fire in
            delays.append(delay)
            let timer = timer(after: delay, fire: fire)
            timers.append(timer)
            return timer
        }, action: { fired += 1 })
        defer { monitor.stop() }
        monitor.poll()
        // The main thread first notices the press 0.8 seconds after its physical down event.
        sample = snapshot(at: 0.925, counts: [1, 0, 0, 0, 0], ages: [0.9, 10, 10, 10, 10], modifierAge: 0.8)
        monitor.poll()
        #expect(delays.count == 1)
        #expect(abs(delays[0] - 0.2) < 0.000001)
        let deadline = try #require(timers.first)
        sample.time = 1; monitor.poll()
        #expect(fired == 0)
        sample.time = 1.125; deadline.fire()
        #expect(fired == 1)
        #expect(!deadline.isValid)
    }

    @Test func verifiedFirstSamplePastOneSecondFiresWithoutAnotherTimerOrRelease() {
        var sample = snapshot(at: 0, held: false, modifierCount: 0)
        var scheduled = 0
        var fired = 0
        let monitor = ControlHoldMonitor(readSnapshot: { sample }, scheduleDeadline: { delay, fire in
            scheduled += 1
            return timer(after: delay, fire: fire)
        }, action: { fired += 1 })
        defer { monitor.stop() }
        monitor.poll()
        sample = snapshot(at: 1.25, modifierAge: 1.125); monitor.poll()
        #expect(fired == 1)
        #expect(scheduled == 0)
        sample.time = 1.375; monitor.poll()
        #expect(fired == 1)
    }

    @Test func sessionResetRejectsAPreviouslyConfirmedButUnobservedPress() {
        let center = NotificationCenter()
        var sample = snapshot(at: 0, held: false, modifierCount: 0)
        var scheduled = 0
        var fired = 0
        let monitor = ControlHoldMonitor(readSnapshot: { sample }, notificationCenter: center,
            scheduleDeadline: { delay, fire in
                scheduled += 1
                return timer(after: delay, fire: fire)
            }, action: { fired += 1 })
        defer { monitor.stop() }
        monitor.start()
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        sample = snapshot(at: 2.25, modifierAge: 2.125); monitor.poll()
        #expect(fired == 0)
        #expect(scheduled == 0)
    }

    @Test func invalidAndPreReleaseModifierAgesDoNotScheduleAnEarlyDeadline() {
        for age in [Double.nan, .infinity, -0.1, 0.125, 0.5, 1] {
            var sample = snapshot(at: 0, held: false, modifierCount: 0)
            var scheduled = 0
            var fired = 0
            let monitor = ControlHoldMonitor(readSnapshot: { sample }, scheduleDeadline: { delay, fire in
                scheduled += 1
                return timer(after: delay, fire: fire)
            }, action: { fired += 1 })
            defer { monitor.stop() }
            monitor.poll()
            sample = snapshot(at: 0.125, modifierAge: age); monitor.poll()
            for tick in 2...30 { sample.time = Double(tick) / 8; monitor.poll() }
            #expect(scheduled == 0)
            #expect(fired == 0)
        }
    }

    private func snapshot(at time: TimeInterval, held: Bool = true, counts: [UInt32] = [0, 0, 0, 0, 0],
                          ages: [TimeInterval] = [10, 10, 10, 10, 10], modifierCount: UInt32 = 1,
                          modifierAge: TimeInterval = 0.05) -> ControlHoldMonitor.Snapshot {
        .init(time: time, controlHeld: held, otherModifierHeld: false, mouseButtonHeld: false,
              ordinaryKeyHeld: false, inputCounts: counts, inputAges: ages,
              modifierCount: modifierCount, modifierAge: modifierAge)
    }

    @Test func completedInputBeforeControlDoesNotCancelTheHold() {
        for input in 0..<5 {
            var sample = snapshot(at: 0, held: false, modifierCount: 0)
            var fired = 0
            let monitor = ControlHoldMonitor(readSnapshot: { sample }, action: { fired += 1 })
            monitor.poll()
            var counts: [UInt32] = [0, 0, 0, 0, 0]
            counts[input] = 1
            sample = snapshot(at: 0.1, counts: counts, modifierAge: 0.05)
            // The ordinary input ended before Control was pressed in the same sampling interval.
            var ages: [TimeInterval] = [10, 10, 10, 10, 10]
            ages[input] = 0.08
            sample.inputAges = ages
            monitor.poll()
            for tick in 2...22 { sample.time = Double(tick) / 10; monitor.poll() }
            #expect(fired == 1)
        }
    }

    @Test func firstSampleRejectsInputAfterControlAndAmbiguousTiming() {
        for age in [0.02, 0.05, .nan, .infinity] {
            var sample = snapshot(at: 0, held: false, modifierCount: 0)
            var fired = 0
            let monitor = ControlHoldMonitor(readSnapshot: { sample }, action: { fired += 1 })
            monitor.poll()
            sample = snapshot(at: 0.1, counts: [1, 0, 0, 0, 0], ages: [age, 10, 10, 10, 10])
            monitor.poll()
            for tick in 2...30 { sample.time = Double(tick) / 10; monitor.poll() }
            #expect(fired == 0)
        }
    }

    @Test func briefInputBetweenHeldSamplesStillCancelsUntilRelease() {
        var sample = snapshot(at: 0, held: false, modifierCount: 0)
        var fired = 0
        let monitor = ControlHoldMonitor(readSnapshot: { sample }, action: { fired += 1 })
        monitor.poll()
        sample = snapshot(at: 0.1); monitor.poll()
        sample = snapshot(at: 0.2, counts: [1, 0, 0, 0, 0]); monitor.poll()
        for tick in 3...30 { sample.time = Double(tick) / 10; monitor.poll() }
        #expect(fired == 0)
        sample = snapshot(at: 3.1, held: false, counts: [1, 0, 0, 0, 0], modifierCount: 2); monitor.poll()
        sample = snapshot(at: 3.2, counts: [1, 0, 0, 0, 0], modifierCount: 3); monitor.poll()
        for tick in 33...53 { sample.time = Double(tick) / 10; monitor.poll() }
        #expect(fired == 1)
    }

    @Test func extraModifierTransitionsInTheFirstSampleCancelTheHold() {
        var sample = snapshot(at: 0, held: false, modifierCount: 0)
        var fired = 0
        let monitor = ControlHoldMonitor(readSnapshot: { sample }, action: { fired += 1 })
        monitor.poll()
        // Control down, Shift down and Shift up all occurred before the next sample.
        sample = snapshot(at: 0.1, modifierCount: 3); monitor.poll()
        for tick in 2...30 { sample.time = Double(tick) / 10; monitor.poll() }
        #expect(fired == 0)
    }

    @Test func sleepWakeAndSessionTransitionsRequireAFreshRelease() {
        let center = NotificationCenter()
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            var sample = snapshot(at: 0, held: false, modifierCount: 0)
            var fired = 0
            var suspended = 0
            let monitor = ControlHoldMonitor(readSnapshot: { sample }, notificationCenter: center,
                onSuspend: { suspended += 1 }, action: { fired += 1 })
            monitor.start()
            sample = snapshot(at: 0.1); monitor.poll()
            for tick in 2...5 { sample.time = Double(tick) / 10; monitor.poll() }
            center.post(name: name, object: nil)
            #expect(suspended == (name == NSWorkspace.willSleepNotification || name == NSWorkspace.sessionDidResignActiveNotification ? 1 : 0))
            for tick in 6...35 { sample.time = Double(tick) / 10; monitor.poll() }
            #expect(fired == 0)
            sample = snapshot(at: 3.6, held: false, modifierCount: 2); monitor.poll()
            sample = snapshot(at: 3.7, modifierCount: 3); monitor.poll()
            for tick in 38...59 { sample.time = Double(tick) / 10; monitor.poll() }
            #expect(fired == 1)
            monitor.stop()
        }
    }

    @Test func stoppingRemovesWorkspaceObservers() {
        let center = NotificationCenter()
        var sample = snapshot(at: 0, held: false, modifierCount: 0)
        var fired = 0
        let monitor = ControlHoldMonitor(readSnapshot: { sample }, notificationCenter: center, action: { fired += 1 })
        monitor.start(); monitor.stop()
        monitor.poll()
        sample = snapshot(at: 0.1); monitor.poll()
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        for tick in 2...22 { sample.time = Double(tick) / 10; monitor.poll() }
        #expect(fired == 1)
    }
}
