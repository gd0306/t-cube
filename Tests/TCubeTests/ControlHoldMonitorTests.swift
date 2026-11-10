import AppKit
import Testing
@testable import TCube

@MainActor
struct ControlHoldMonitorTests {
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
            for tick in 2...10 { sample.time = Double(tick) / 10; monitor.poll() }
            center.post(name: name, object: nil)
            #expect(suspended == (name == NSWorkspace.willSleepNotification || name == NSWorkspace.sessionDidResignActiveNotification ? 1 : 0))
            for tick in 11...35 { sample.time = Double(tick) / 10; monitor.poll() }
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
