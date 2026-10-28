import AppKit
import Testing
import CubeCore
@testable import TCube

@MainActor
@Suite(.serialized)
struct CubeHoverTests {
    @Test func nativeModifierChangeShrinksWithoutMouseMovementOrClick() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(store: ConfigurationStore(url: directory.appendingPathComponent("settings.json")))
        let view = CubeView(model: model)
        let surface = CubeSurfaceView(cubeView: view)
        let (window, controller) = fixture(settings: CubeHoverSettings(multiplier: 4, delaySeconds: 0))
        defer { window.orderOut(nil); try? FileManager.default.removeItem(at: directory) }
        window.contentView = surface
        surface.input.modifierFlagsChanged = { controller.modifierFlagsChanged($0, at: $1) }
        controller.pointerChanged(to: CGPoint(x: 250, y: 250))
        func modifierEvent(_ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 59))
        }
        surface.input.flagsChanged(with: try modifierEvent([.control]))
        #expect(window.frame == CGRect(x: 200, y: 200, width: 100, height: 100))
        surface.input.flagsChanged(with: try modifierEvent([]))
        #expect(window.frame == CGRect(x: 50, y: 50, width: 400, height: 400))
    }

    @Test func controlTemporarilyRestoresSmallSizeWithoutSavingOrDrift() {
        let (window, controller) = fixture(settings: CubeHoverSettings(multiplier: 4, delaySeconds: 0))
        defer { window.orderOut(nil) }
        var saves = 0
        controller.onRestingPositionChange = { _ in saves += 1 }
        controller.pointerChanged(to: CGPoint(x: 250, y: 250))
        for _ in 0..<5 {
            controller.modifierFlagsChanged([.control], at: CGPoint(x: 410, y: 390))
            #expect(window.frame == CGRect(x: 320, y: 305, width: 100, height: 100))
            #expect(window.frame.contains(CGPoint(x: 410, y: 390)))
            controller.modifierFlagsChanged([])
            #expect(window.frame == CGRect(x: 50, y: 50, width: 400, height: 400))
        }
        #expect(saves == 0)
        controller.pointerChanged(to: CGPoint(x: 700, y: 700))
        #expect(window.frame == CGRect(x: 200, y: 200, width: 100, height: 100))
    }

    @Test func enteringWithControlHeldStaysSmallThenReleaseEnlarges() {
        let (window, controller) = fixture(settings: CubeHoverSettings(multiplier: 4, delaySeconds: 0))
        defer { window.orderOut(nil) }
        controller.modifierFlagsChanged([.control], at: CGPoint(x: 600, y: 600))
        controller.pointerChanged(to: CGPoint(x: 250, y: 250))
        #expect(window.frame == CGRect(x: 200, y: 200, width: 100, height: 100))
        controller.modifierFlagsChanged([])
        #expect(window.frame == CGRect(x: 50, y: 50, width: 400, height: 400))
    }

    @Test func releasingControlDuringDragKeepsSmallSizeUntilMouseUp() {
        let (window, controller) = fixture(settings: CubeHoverSettings(multiplier: 4, delaySeconds: 0))
        defer { window.orderOut(nil) }
        var saved: CGPoint?
        controller.onRestingPositionChange = { saved = $0 }
        controller.pointerChanged(to: CGPoint(x: 250, y: 250))
        controller.modifierFlagsChanged([.control])
        controller.setInteractionActive(true)
        controller.modifierFlagsChanged([])
        #expect(window.frame.size == CGSize(width: 100, height: 100))
        window.setFrameOrigin(CGPoint(x: 240, y: 225))
        controller.commitMovedFrame(window.frame)
        #expect(saved == CGPoint(x: 240, y: 225))
        controller.setInteractionActive(false)
        #expect(window.frame == CGRect(x: 90, y: 75, width: 400, height: 400))
        controller.pointerChanged(to: CGPoint(x: 800, y: 700))
        #expect(window.frame == CGRect(x: 240, y: 225, width: 100, height: 100))
    }

    @Test func committingControlDragKeepsMovedSmallPositionWhileControlRemainsHeld() {
        let (window, controller) = fixture(settings: CubeHoverSettings(multiplier: 4, delaySeconds: 0))
        defer { window.orderOut(nil) }
        controller.pointerChanged(to: CGPoint(x: 250, y: 250))
        controller.modifierFlagsChanged([.control], at: CGPoint(x: 410, y: 390))
        controller.setInteractionActive(true)
        window.setFrameOrigin(CGPoint(x: 360, y: 330))
        controller.commitMovedFrame(window.frame)
        controller.setInteractionActive(false)
        #expect(window.frame == CGRect(x: 360, y: 330, width: 100, height: 100))
        controller.modifierFlagsChanged([])
        #expect(window.frame == CGRect(x: 210, y: 180, width: 400, height: 400))
    }

    @Test func nativePointerEntryEnlargesWithoutPressingAnyMouseButton() throws {
        _ = NSApplication.shared
        let model = AppModel(store: ConfigurationStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("settings.json")))
        let view = CubeView(model: model)
        let surface = CubeSurfaceView(cubeView: view)
        let (window, controller) = fixture(settings: CubeHoverSettings(delaySeconds: 0))
        defer { window.orderOut(nil) }
        window.contentView = surface
        controller.onHoverChange = { view.setHovered($0) }
        surface.input.hoverPointChanged = { controller.pointerChanged(to: $0) }
        func crossing(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try #require(NSEvent.enterExitEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, trackingNumber: 1, userData: nil))
        }
        surface.input.mouseEntered(with: try crossing(.mouseEntered, CGPoint(x: 50, y: 50)))
        #expect(window.frame == CGRect(x: 50, y: 50, width: 400, height: 400))
        #expect(view.isHovered)
        surface.input.mouseExited(with: try crossing(.mouseExited, CGPoint(x: 500, y: 500)))
        #expect(window.frame == CGRect(x: 200, y: 200, width: 100, height: 100))
        #expect(!view.isHovered)
    }

    @Test func nativePrimaryDragCommitsTheSmallFrameAfterHoverEnlargement() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ConfigurationStore(url: directory.appendingPathComponent("settings.json"))
        let model = AppModel(store: store)
        let view = CubeView(model: model)
        let surface = CubeSurfaceView(cubeView: view)
        let (window, controller) = fixture()
        defer { window.orderOut(nil); try? FileManager.default.removeItem(at: directory) }
        window.contentView = surface
        controller.onHoverChange = { view.setHovered($0) }
        controller.onRestingPositionChange = { model.savePosition($0) }
        view.interactionChanged = { controller.setInteractionActive($0) }
        view.positionCommitted = { controller.commitMovedFrame($0) }
        controller.pointerChanged(to: CGPoint(x: 250, y: 250))
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        surface.input.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 50, y: 50)))
        surface.input.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 90, y: 75)))
        surface.input.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 50, y: 50)))
        #expect(try store.load().windowPosition == WindowPosition(x: 240, y: 225))
        controller.pointerChanged(to: CGPoint(x: 500, y: 500))
        #expect(window.frame == CGRect(x: 240, y: 225, width: 100, height: 100))
    }

    @Test func pointerEntryEnlargesAndExitRestoresWithoutSaving() {
        let (window, controller) = fixture()
        defer { window.orderOut(nil) }
        var saves = 0
        controller.onRestingPositionChange = { _ in saves += 1 }
        controller.pointerChanged(to: CGPoint(x: 250, y: 250))
        #expect(window.frame == CGRect(x: 170, y: 170, width: 160, height: 160))
        controller.pointerChanged(to: CGPoint(x: 320, y: 250))
        #expect(window.frame.width == 160)
        controller.pointerChanged(to: CGPoint(x: 500, y: 500))
        #expect(window.frame == CGRect(x: 200, y: 200, width: 100, height: 100))
        #expect(saves == 0)
    }

    @Test func repeatedHoverAtScreenEdgeDoesNotDrift() {
        let (window, controller) = fixture(origin: .zero)
        defer { window.orderOut(nil) }
        for _ in 0..<12 {
            controller.pointerChanged(to: CGPoint(x: 30, y: 30))
            #expect(window.frame == CGRect(x: 0, y: 0, width: 160, height: 160))
            controller.pointerChanged(to: CGPoint(x: 500, y: 500))
            #expect(window.frame == CGRect(x: 0, y: 0, width: 100, height: 100))
        }
    }

    @Test func pointerGestureHoldsGeometryUntilRelease() {
        let (window, controller) = fixture()
        defer { window.orderOut(nil) }
        controller.pointerChanged(to: CGPoint(x: 250, y: 250))
        controller.setInteractionActive(true)
        controller.pointerChanged(to: CGPoint(x: 500, y: 500))
        #expect(window.frame.width == 160)
        controller.setInteractionActive(false)
        #expect(window.frame == CGRect(x: 200, y: 200, width: 100, height: 100))
    }

    @Test func enlargedDragSavesRestingPositionRatherThanEnlargedOrigin() {
        let (window, controller) = fixture(origin: .zero)
        defer { window.orderOut(nil) }
        var saved: CGPoint?
        controller.onRestingPositionChange = { saved = $0 }
        controller.pointerChanged(to: CGPoint(x: 30, y: 30))
        controller.setInteractionActive(true)
        window.setFrameOrigin(CGPoint(x: 20, y: 30))
        controller.commitMovedFrame(window.frame)
        #expect(saved == CGPoint(x: 50, y: 60))
        controller.setInteractionActive(false)
        #expect(window.frame == CGRect(x: 20, y: 30, width: 160, height: 160))
        controller.pointerChanged(to: CGPoint(x: 500, y: 500))
        #expect(window.frame == CGRect(x: 50, y: 60, width: 100, height: 100))
    }

    @Test func disablingHoverRestoresSizeAndSizeEditsKeepRestingCenter() {
        let (window, controller) = fixture()
        defer { window.orderOut(nil) }
        controller.pointerChanged(to: CGPoint(x: 250, y: 250))
        controller.configure(baseSize: CGSize(width: 120, height: 120), settings: CubeHoverSettings(isEnabled: false, delaySeconds: 0))
        #expect(window.frame == CGRect(x: 190, y: 190, width: 120, height: 120))
    }

    private func fixture(origin: CGPoint = CGPoint(x: 200, y: 200), settings: CubeHoverSettings = CubeHoverSettings(multiplier: 1.6, delaySeconds: 0)) -> (NSPanel, CubeHoverController) {
        _ = NSApplication.shared
        let window = NSPanel(contentRect: CGRect(origin: origin, size: CGSize(width: 100, height: 100)), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.orderFrontRegardless()
        let controller = CubeHoverController(window: window, settings: settings, screens: { [CGRect(x: 0, y: 0, width: 1000, height: 800)] })
        return (window, controller)
    }
}
