import Testing
@testable import CubeCore

struct ControlHoldGestureTests {
    @Test func onlyAContinuousTwoSecondHoldFiresOnce() {
        var gesture = ControlHoldGesture()
        #expect(gesture.update(controlHeld: false, interrupted: false, at: 0) == false)
        #expect(gesture.update(controlHeld: true, interrupted: false, at: 1) == false)
        for tick in 1...19 {
            #expect(gesture.update(controlHeld: true, interrupted: false, at: 1 + Double(tick) / 10) == false)
        }
        #expect(gesture.update(controlHeld: true, interrupted: false, at: 3) == true)
        #expect(gesture.update(controlHeld: true, interrupted: false, at: 3.1) == false)
        #expect(gesture.update(controlHeld: false, interrupted: false, at: 3.2) == false)
        #expect(gesture.update(controlHeld: true, interrupted: false, at: 4) == false)
        for tick in 1...19 { _ = gesture.update(controlHeld: true, interrupted: false, at: 4 + Double(tick) / 10) }
        #expect(gesture.update(controlHeld: true, interrupted: false, at: 6) == true)
    }

    @Test func combinationsAndMouseActionsRequireControlToBeReleased() {
        var gesture = ControlHoldGesture()
        _ = gesture.update(controlHeld: false, interrupted: false, at: 0)
        _ = gesture.update(controlHeld: true, interrupted: false, at: 0.1)
        _ = gesture.update(controlHeld: true, interrupted: true, at: 0.2)
        for tick in 3...40 { #expect(gesture.update(controlHeld: true, interrupted: false, at: Double(tick) / 10) == false) }
        _ = gesture.update(controlHeld: false, interrupted: false, at: 4.1)
        _ = gesture.update(controlHeld: true, interrupted: false, at: 4.2)
        _ = gesture.update(controlHeld: false, interrupted: false, at: 4.3)
        for tick in 44...70 { #expect(gesture.update(controlHeld: false, interrupted: false, at: Double(tick) / 10) == false) }
    }

    @Test func startupHeldControlAndSuspendedSamplingNeverFire() {
        var gesture = ControlHoldGesture()
        for tick in 0...30 { #expect(gesture.update(controlHeld: true, interrupted: false, at: Double(tick) / 10) == false) }
        _ = gesture.update(controlHeld: false, interrupted: false, at: 3.1)
        _ = gesture.update(controlHeld: true, interrupted: false, at: 3.2)
        #expect(gesture.update(controlHeld: true, interrupted: false, at: 30) == false)
        for tick in 1...30 { #expect(gesture.update(controlHeld: true, interrupted: false, at: 30 + Double(tick) / 10) == false) }
    }
}
