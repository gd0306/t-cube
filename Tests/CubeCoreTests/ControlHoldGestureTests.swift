import Testing
@testable import CubeCore

struct ControlHoldGestureTests {
    @Test func verifiedPhysicalPressReachesOneSecondBeforeTheNextPollingTick() {
        var gesture = ControlHoldGesture()
        _ = gesture.update(controlHeld: false, interrupted: false, at: 0)
        #expect(gesture.update(controlHeld: true, interrupted: false, at: 0.125, pressedAt: 0.0625) == false)
        for tick in 2...8 {
            #expect(gesture.update(controlHeld: true, interrupted: false, at: Double(tick) / 8) == false)
        }
        #expect(gesture.update(controlHeld: true, interrupted: false, at: 1.0624) == false)
        #expect(gesture.update(controlHeld: true, interrupted: false, at: 1.0625) == true)
        #expect(gesture.update(controlHeld: true, interrupted: false, at: 1.125, pressedAt: 0.0625) == false)
    }

    @Test func delayedFirstSampleStillUsesThePhysicalOneSecondDeadline() {
        var gesture = ControlHoldGesture()
        _ = gesture.update(controlHeld: false, interrupted: false, at: 0)
        #expect(gesture.update(controlHeld: true, interrupted: false, at: 0.925, pressedAt: 0.125) == false)
        #expect(gesture.deadline == 1.125)
        #expect(gesture.update(controlHeld: true, interrupted: false, at: 1) == false)
        #expect(gesture.update(controlHeld: true, interrupted: false, at: 1.1249) == false)
        #expect(gesture.update(controlHeld: true, interrupted: false, at: 1.125) == true)
    }

    @Test func firstSampleAfterOnePhysicalSecondFiresImmediatelyWhenTheOriginIsConfirmed() {
        var gesture = ControlHoldGesture()
        _ = gesture.update(controlHeld: false, interrupted: false, at: 0)
        #expect(gesture.update(controlHeld: true, interrupted: false, at: 1.25, pressedAt: 0.125) == true)
        #expect(gesture.deadline == nil)
        #expect(gesture.update(controlHeld: true, interrupted: false, at: 1.375) == false)
    }

    @Test func invalidAndUnconfirmedOriginsCannotAdvanceTheDeadline() {
        for origin in [Double.nan, .infinity, 10.25, 9.99, 10] {
            var gesture = ControlHoldGesture()
            _ = gesture.update(controlHeld: false, interrupted: false, at: 10)
            _ = gesture.update(controlHeld: true, interrupted: false, at: 10.125, pressedAt: origin)
            for tick in 2...30 {
                #expect(gesture.update(controlHeld: true, interrupted: false, at: 10 + Double(tick) / 8) == false)
            }
        }
    }

    @Test func suppliedOriginCannotBypassStartupOrInterruptionGates() {
        var startup = ControlHoldGesture()
        for tick in 1...30 {
            #expect(startup.update(controlHeld: true, interrupted: false, at: Double(tick) / 8, pressedAt: 0.0625) == false)
        }
        var interrupted = ControlHoldGesture()
        _ = interrupted.update(controlHeld: false, interrupted: false, at: 0)
        _ = interrupted.update(controlHeld: true, interrupted: true, at: 0.125, pressedAt: 0.0625)
        for tick in 2...30 {
            #expect(interrupted.update(controlHeld: true, interrupted: false, at: Double(tick) / 8, pressedAt: 0.0625) == false)
        }
    }

    @Test func onlyAContinuousOneSecondHoldFiresOnce() {
        var gesture = ControlHoldGesture()
        #expect(gesture.update(controlHeld: false, interrupted: false, at: 0) == false)
        #expect(gesture.update(controlHeld: true, interrupted: false, at: 1) == false)
        for tick in 1...9 {
            #expect(gesture.update(controlHeld: true, interrupted: false, at: 1 + Double(tick) / 10) == false)
        }
        #expect(gesture.update(controlHeld: true, interrupted: false, at: 2) == true)
        #expect(gesture.update(controlHeld: true, interrupted: false, at: 2.1) == false)
        #expect(gesture.update(controlHeld: false, interrupted: false, at: 2.2) == false)
        #expect(gesture.update(controlHeld: true, interrupted: false, at: 3) == false)
        for tick in 1...9 { _ = gesture.update(controlHeld: true, interrupted: false, at: 3 + Double(tick) / 10) }
        #expect(gesture.update(controlHeld: true, interrupted: false, at: 4) == true)
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
