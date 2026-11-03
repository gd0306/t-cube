import Foundation
import Testing
@testable import CubeCore

struct DesktopAutoHideTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let cube = CGRect(x: 24, y: 300, width: 180, height: 180)

    @Test func onlyOuterSideEdgesOfferAnAccessibleBoundedHandle() {
        let handle = DesktopAutoHideGeometry.handle(resting: cube, screens: [screen])
        #expect(handle == CGRect(x: 0, y: 362, width: 10, height: 56))
        #expect(DesktopAutoHideGeometry.handle(resting: CGRect(x: 500, y: 300, width: 180, height: 180), screens: [screen]) == nil)
        #expect(DesktopAutoHideGeometry.handle(resting: cube, screens: [screen, CGRect(x: -1000, y: 0, width: 1000, height: 900)]) == nil)
        let right = CGRect(x: 1236, y: 870, width: 180, height: 180)
        let bottomScreen = CGRect(x: 0, y: 0, width: 1440, height: 1080)
        #expect(DesktopAutoHideGeometry.handle(resting: right, screens: [bottomScreen])?.maxX == 1440)
        #expect(DesktopAutoHideGeometry.handle(resting: cube, screens: []) == nil)
        let usable = CGRect(x: 60, y: 0, width: 1380, height: 900)
        #expect(DesktopAutoHideGeometry.handle(resting: CGRect(x: 84, y: 300, width: 180, height: 180),
            screens: [usable, CGRect(x: -1000, y: 0, width: 1000, height: 900)],
            physicalScreens: [screen, CGRect(x: -1000, y: 0, width: 1000, height: 900)]) == nil)
    }

    @Test func collapseWaitsForDepartureAndProtectsInteractions() {
        var state = DesktopAutoHideState()
        #expect(state.update(edgeEnabled: true, edgeAvailable: true, fullscreen: false, pointerInside: false, busy: false, now: 0) == .cube)
        #expect(state.update(edgeEnabled: true, edgeAvailable: true, fullscreen: false, pointerInside: false, busy: false, now: 0.9) == .edge)
        #expect(state.update(edgeEnabled: true, edgeAvailable: true, fullscreen: false, pointerInside: true, busy: false, now: 1) == .cube)
        #expect(state.update(edgeEnabled: true, edgeAvailable: true, fullscreen: false, pointerInside: false, busy: true, now: 9) == .cube)
        #expect(state.update(edgeEnabled: true, edgeAvailable: false, fullscreen: false, pointerInside: false, busy: false, now: 10) == .cube)
    }

    @Test func manualHideIsIndependentOfFullscreenAndExplicitShowCanOverrideIt() {
        var state = DesktopAutoHideState()
        #expect(state.update(edgeEnabled: false, edgeAvailable: false, fullscreen: true, pointerInside: false, busy: false, now: 0) == .hidden)
        state.setUserVisible(false)
        #expect(state.update(edgeEnabled: false, edgeAvailable: false, fullscreen: false, pointerInside: false, busy: false, now: 1) == .hidden)
        state.setUserVisible(true)
        #expect(state.update(edgeEnabled: false, edgeAvailable: false, fullscreen: true, pointerInside: false, busy: false, now: 2) == .hidden)
        state.reveal()
        #expect(state.update(edgeEnabled: false, edgeAvailable: false, fullscreen: true, pointerInside: false, busy: false, now: 3) == .cube)
        _ = state.update(edgeEnabled: false, edgeAvailable: false, fullscreen: false, pointerInside: false, busy: false, now: 4)
        #expect(state.update(edgeEnabled: false, edgeAvailable: false, fullscreen: true, pointerInside: false, busy: false, now: 5) == .hidden)
    }

    @Test func fullscreenRequiresDisplayCoverageAndAllowsTheNotchStrip() {
        #expect(DesktopAutoHideGeometry.isFullscreen(window: screen, screen: screen))
        #expect(!DesktopAutoHideGeometry.isFullscreen(window: screen.insetBy(dx: 0, dy: 24), screen: screen))
        #expect(DesktopAutoHideGeometry.isFullscreen(window: CGRect(x: 0, y: 0, width: 1440, height: 868), screen: screen, safeTop: 32))
        #expect(!DesktopAutoHideGeometry.isFullscreen(window: CGRect(x: 0, y: 25, width: 1440, height: 843), screen: screen, safeTop: 32))
    }
}
