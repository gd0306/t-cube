import AppKit
import CubeCore
import Testing
@testable import TCube

@MainActor
@Suite(.serialized)
struct ControlHoldConflictTests {
    @Test func leavingBeforePressingControlDoesNotReserveAnOutsideHold() {
        let (window, hover) = fixture()
        defer { window.orderOut(nil) }
        let outside = NSPoint(x: 700, y: 700)
        hover.pointerChanged(to: NSPoint(x: 250, y: 250))
        hover.modifierFlagsChanged([], at: outside)
        hover.pointerChanged(to: outside)
        hover.modifierFlagsChanged([.control], at: outside)
        #expect(!hover.reservesControlHold(held: true, at: outside))
    }

    @Test func firstControlSampleOnPointerExitRetainsThePreviousCubeHover() {
        let (window, hover) = fixture()
        defer { window.orderOut(nil) }
        var pointer = NSPoint(x: 250, y: 250)
        var sample = snapshot(0, held: false)
        var opened = 0
        let monitor = ControlHoldMonitor(readSnapshot: { sample }, action: { opened += 1 })
        monitor.controlReserved = { hover.reservesControlHold(held: $0, at: pointer) }
        defer { monitor.stop() }
        monitor.poll()
        hover.pointerChanged(to: pointer)
        pointer = NSPoint(x: 700, y: 700)
        // The first event carrying Control is already outside, before modifier polling ran.
        hover.modifierFlagsChanged([.control], at: pointer)
        hover.pointerChanged(to: pointer)
        sample = snapshot(0.125); monitor.poll()
        for tick in 2...16 { sample.time = Double(tick) / 8; monitor.poll() }
        #expect(opened == 0)
    }

    @Test func shrinkingThenLeavingTheCubeKeepsThisHoldReservedUntilRelease() {
        let (window, hover) = fixture()
        defer { window.orderOut(nil) }
        var pointer = NSPoint(x: 250, y: 250)
        var sample = snapshot(0, held: false)
        var opened = 0
        let monitor = ControlHoldMonitor(readSnapshot: { sample }, action: { opened += 1 })
        monitor.controlReserved = { hover.reservesControlHold(held: $0, at: pointer) }
        defer { monitor.stop() }
        monitor.poll()
        hover.pointerChanged(to: pointer)
        #expect(window.frame.width == 400)
        pointer = NSPoint(x: 410, y: 390)
        hover.modifierFlagsChanged([.control], at: pointer)
        #expect(window.frame.width == 100)
        #expect(window.frame.contains(pointer))
        sample = snapshot(0.125); monitor.poll()
        #expect(hover.reservesControlHold(held: true, at: pointer))
        pointer = NSPoint(x: 700, y: 700)
        hover.pointerChanged(to: pointer)
        for tick in 2...16 { sample.time = Double(tick) / 8; monitor.poll() }
        #expect(opened == 0)
        // The monitor observes release even after the cube's own modifier timer stops.
        sample = snapshot(2.125, held: false, modifiers: 2); monitor.poll()
        sample = snapshot(2.25, modifiers: 3); monitor.poll()
        for tick in 19...26 { sample.time = Double(tick) / 8; monitor.poll() }
        #expect(opened == 1)
    }

    @Test func briefCubeEntryBetweenClipboardSamplesCancelsTheWholeHold() {
        let (window, hover) = fixture()
        defer { window.orderOut(nil) }
        var pointer = NSPoint(x: 700, y: 700)
        var sample = snapshot(0, held: false)
        var opened = 0
        let monitor = ControlHoldMonitor(readSnapshot: { sample }, action: { opened += 1 })
        monitor.controlReserved = { hover.reservesControlHold(held: $0, at: pointer) }
        defer { monitor.stop() }
        monitor.poll()
        hover.modifierFlagsChanged([.control], at: pointer)
        sample = snapshot(0.125); monitor.poll()
        // Pointer tracking sees entry and exit before the next clipboard poll.
        hover.pointerChanged(to: NSPoint(x: 250, y: 250))
        hover.pointerChanged(to: pointer)
        for tick in 2...16 { sample.time = Double(tick) / 8; monitor.poll() }
        #expect(opened == 0)
        #expect(hover.reservesControlHold(held: true, at: pointer))
    }

    @Test func clipboardSamplingCanClaimTheCubeBeforeItsModifierHandlerRuns() {
        let (window, hover) = fixture()
        defer { window.orderOut(nil) }
        hover.pointerChanged(to: NSPoint(x: 250, y: 250))
        #expect(hover.reservesControlHold(held: true, at: NSPoint(x: 410, y: 390)))
        #expect(hover.reservesControlHold(held: true, at: NSPoint(x: 700, y: 700)))
        #expect(!hover.reservesControlHold(held: false, at: NSPoint(x: 700, y: 700)))
        #expect(!hover.reservesControlHold(held: true, at: NSPoint(x: 700, y: 700)))
    }

    @Test func activeCubeDragReservesControlButHiddenCubeDoesNotClaimANewHold() {
        let (window, hover) = fixture()
        defer { window.orderOut(nil) }
        let outside = NSPoint(x: 700, y: 700)
        hover.setInteractionActive(true)
        #expect(hover.reservesControlHold(held: true, at: outside))
        hover.setInteractionActive(false)
        #expect(hover.reservesControlHold(held: true, at: outside))
        #expect(!hover.reservesControlHold(held: false, at: outside))
        window.orderOut(nil)
        #expect(!hover.reservesControlHold(held: true, at: NSPoint(x: 250, y: 250)))
    }

    private func fixture() -> (NSPanel, CubeHoverController) {
        _ = NSApplication.shared
        let window = NSPanel(contentRect: NSRect(x: 200, y: 200, width: 100, height: 100),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.orderFrontRegardless()
        return (window, CubeHoverController(window: window,
            settings: CubeHoverSettings(multiplier: 4, delaySeconds: 0),
            screens: { [NSRect(x: 0, y: 0, width: 1000, height: 1000)] }))
    }

    private func snapshot(_ time: TimeInterval, held: Bool = true, modifiers: UInt32 = 1) -> ControlHoldMonitor.Snapshot {
        .init(time: time, controlHeld: held, otherModifierHeld: false, mouseButtonHeld: false,
              ordinaryKeyHeld: false, inputCounts: [0, 0, 0, 0, 0], inputAges: [10, 10, 10, 10, 10],
              modifierCount: held ? modifiers : (time == 0 ? 0 : modifiers), modifierAge: 0.0625)
    }
}
