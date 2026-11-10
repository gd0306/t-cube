import AppKit
import CubeCore

/// Reads modifier state and event counts, never keyboard text, without capturing or suppressing input.
@MainActor
final class ControlHoldMonitor {
    typealias DeadlineScheduler = (TimeInterval, @escaping @MainActor () -> Void) -> Timer
    struct Snapshot {
        var time: TimeInterval
        var controlHeld: Bool
        var otherModifierHeld: Bool
        var mouseButtonHeld: Bool
        var ordinaryKeyHeld: Bool
        var inputCounts: [UInt32]
        var inputAges: [TimeInterval]
        var modifierCount: UInt32
        var modifierAge: TimeInterval
    }

    private var gesture = ControlHoldGesture()
    private var previous: Snapshot?
    private let readSnapshot: () -> Snapshot
    private let resources: ControlHoldMonitoringResources
    private let scheduleDeadline: DeadlineScheduler
    private let onSuspend: () -> Void
    private let action: () -> Void
    private static let events: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
    private static let modifiers: Set<CGKeyCode> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    init(readSnapshot: (() -> Snapshot)? = nil,
         notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         scheduleDeadline: DeadlineScheduler? = nil,
         onSuspend: @escaping () -> Void = {}, action: @escaping () -> Void) {
        self.readSnapshot = readSnapshot ?? Self.captureSnapshot
        resources = ControlHoldMonitoringResources(center: notificationCenter)
        self.scheduleDeadline = scheduleDeadline ?? Self.makeDeadlineTimer
        self.onSuspend = onSuspend
        self.action = action
    }

    func start() {
        stop()
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            let suspending = name == NSWorkspace.willSleepNotification || name == NSWorkspace.sessionDidResignActiveNotification
            let token = resources.center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.resetGesture()
                    if suspending { self?.onSuspend() }
                }
            }
            resources.observers.append(token)
        }
        poll()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.01
        resources.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        resources.clear()
        resetGesture()
    }

    private func resetGesture() {
        resources.clearDeadline()
        gesture = ControlHoldGesture()
        previous = nil
    }

    func poll() {
        let sample = readSnapshot()
        var interrupted = sample.otherModifierHeld
        var pressedAt: TimeInterval?
        if sample.controlHeld {
            interrupted = interrupted || sample.mouseButtonHeld || sample.ordinaryKeyHeld
            if let previous {
                if previous.controlHeld {
                    // Counts preserve brief combinations that begin and end between samples.
                    interrupted = interrupted || sample.inputCounts != previous.inputCounts || sample.modifierCount != previous.modifierCount
                } else {
                    // Only one modifier transition is unambiguously a standalone Control press.
                    interrupted = interrupted || sample.modifierCount != previous.modifierCount &+ 1
                    interrupted = interrupted || !sample.modifierAge.isFinite || sample.modifierAge < 0
                    let origin = sample.time - sample.modifierAge
                    if origin.isFinite, origin > previous.time, origin <= sample.time {
                        pressedAt = origin
                    } else {
                        interrupted = true
                    }
                    if sample.inputCounts.count != Self.events.count || sample.inputAges.count != Self.events.count {
                        interrupted = true
                    } else {
                        for index in Self.events.indices where sample.inputCounts[index] != previous.inputCounts[index] {
                            let age = sample.inputAges[index]
                            // Equality and unavailable timing cancel rather than admitting a combination.
                            interrupted = interrupted || !age.isFinite || age <= sample.modifierAge
                        }
                    }
                }
            }
        }
        previous = sample
        let fired = gesture.update(controlHeld: sample.controlHeld, interrupted: interrupted, at: sample.time, pressedAt: pressedAt)
        updateDeadline(at: sample.time)
        if fired { action() }
    }

    private func updateDeadline(at time: TimeInterval) {
        guard gesture.deadline != resources.deadlineAt else { return }
        resources.clearDeadline()
        guard let deadline = gesture.deadline else { return }
        let timer = scheduleDeadline(max(0, deadline - time)) { [weak self] in
            guard let self, self.resources.deadlineAt == deadline else { return }
            self.resources.clearDeadline()
            // The deadline is only an extra sample, never permission to bypass input validation.
            self.poll()
        }
        timer.tolerance = 0
        resources.deadlineAt = deadline
        resources.deadlineTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private static func makeDeadlineTimer(after delay: TimeInterval, fire: @escaping @MainActor () -> Void) -> Timer {
        Timer(timeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated { fire() } }
    }

    private static func captureSnapshot() -> Snapshot {
        let source = CGEventSourceStateID.combinedSessionState
        let flags = CGEventSource.flagsState(source)
        let held = flags.contains(.maskControl)
        let counts = events.map { CGEventSource.counterForEventType(source, eventType: $0) }
        let mouseButtonHeld = held && NSEvent.pressedMouseButtons != 0
        let ordinaryKeyHeld = held && (CGKeyCode(0)...127).contains { key in
            !modifiers.contains(key) && CGEventSource.keyState(source, key: key)
        }
        // Read input ages before the modifier age. The ordering makes near-simultaneous
        // events conservative: only a strictly older input is known to precede Control.
        let ages = events.map { CGEventSource.secondsSinceLastEventType(source, eventType: $0) }
        let modifierCount = CGEventSource.counterForEventType(source, eventType: .flagsChanged)
        let modifierAge = CGEventSource.secondsSinceLastEventType(source, eventType: .flagsChanged)
        // Read uptime after the age: subtraction cannot backdate the press by capture overhead.
        return Snapshot(time: ProcessInfo.processInfo.systemUptime, controlHeld: held,
            otherModifierHeld: !flags.intersection([.maskCommand, .maskAlternate, .maskShift, .maskSecondaryFn]).isEmpty,
            mouseButtonHeld: mouseButtonHeld, ordinaryKeyHeld: ordinaryKeyHeld,
            inputCounts: counts, inputAges: ages, modifierCount: modifierCount, modifierAge: modifierAge)
    }
}

/// Owns run-loop and notification registrations even if the monitor is released without stop().
private final class ControlHoldMonitoringResources {
    let center: NotificationCenter
    var timer: Timer?
    var deadlineTimer: Timer?
    var deadlineAt: TimeInterval?
    var observers: [NSObjectProtocol] = []

    init(center: NotificationCenter) { self.center = center }

    func clear() {
        timer?.invalidate(); timer = nil
        clearDeadline()
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll()
    }

    func clearDeadline() {
        deadlineTimer?.invalidate(); deadlineTimer = nil; deadlineAt = nil
    }

    deinit { clear() }
}
