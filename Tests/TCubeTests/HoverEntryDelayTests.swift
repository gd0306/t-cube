import AppKit
import Testing
import CubeCore
@testable import TCube

@MainActor
@Suite(.serialized)
struct HoverEntryDelayTests {
    @Test func briefPointerCrossingDoesNotEnlargeAndExitIsImmediate() {
        let (window, hover) = fixture()
        defer { hover.stopTrackingPointer(); window.orderOut(nil) }
        hover.pointerChanged(to: CGPoint(x: 250, y: 250))
        #expect(!hover.isHovered)
        #expect(window.frame.width == 100)
        hover.pointerChanged(to: CGPoint(x: 800, y: 700))
        pump(0.09)
        #expect(!hover.isHovered)
        hover.pointerChanged(to: CGPoint(x: 250, y: 250))
        pump(0.09)
        #expect(hover.isHovered)
        #expect(window.frame.width == 200)
        hover.pointerChanged(to: CGPoint(x: 800, y: 700))
        #expect(!hover.isHovered)
        #expect(window.frame.width == 100)
    }

    @Test func resetConfigurationDragAndStopCancelPendingEntry() {
        for action in 0..<4 {
            let (window, hover) = fixture()
            defer { hover.stopTrackingPointer(); window.orderOut(nil) }
            hover.pointerChanged(to: CGPoint(x: 250, y: 250))
            switch action {
            case 0: hover.resetHover()
            case 1: hover.configure(baseSize: CGSize(width: 100, height: 100), settings: CubeHoverSettings(multiplier: 2, delaySeconds: 0.04))
            case 2: hover.setInteractionActive(true)
            default: hover.stopTrackingPointer()
            }
            pump(0.09)
            #expect(!hover.isHovered)
            #expect(window.frame.width == 100)
        }
    }

    @Test func hiddenWindowDoesNotCompletePendingEntryAndControlCanGrabImmediately() {
        let (window, hover) = fixture()
        defer { hover.stopTrackingPointer(); window.orderOut(nil) }
        hover.pointerChanged(to: CGPoint(x: 250, y: 250))
        window.orderOut(nil)
        pump(0.09)
        #expect(!hover.isHovered)
        window.orderFrontRegardless()
        hover.modifierFlagsChanged([.control], at: CGPoint(x: 250, y: 250))
        #expect(hover.isHovered)
        #expect(window.frame.width == 100)
        hover.modifierFlagsChanged([])
        #expect(window.frame.width == 200)
    }

    @Test func enlargementFitsItsDisplayWithoutChangingRestingPosition() {
        _ = NSApplication.shared
        let panel = NSPanel(contentRect: CGRect(x: 100, y: 100, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        let hover = CubeHoverController(window: panel, settings: CubeHoverSettings(multiplier: 4, delaySeconds: 0), screens: { [CGRect(x: 0, y: 40, width: 600, height: 500)] })
        hover.pointerChanged(to: CGPoint(x: 200, y: 200))
        #expect(panel.frame == CGRect(x: 0, y: 40, width: 500, height: 500))
        #expect(hover.restingFrame == CGRect(x: 100, y: 100, width: 200, height: 200))
    }

    private func fixture() -> (NSPanel, CubeHoverController) {
        _ = NSApplication.shared
        let panel = NSPanel(contentRect: CGRect(x: 200, y: 200, width: 100, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.orderFrontRegardless()
        return (panel, CubeHoverController(window: panel, settings: CubeHoverSettings(multiplier: 2, delaySeconds: 0.04), screens: { [CGRect(x: 0, y: 0, width: 1000, height: 800)] }))
    }

    private func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}
