import AppKit
import CubeCore
import Testing
@testable import TCube

@MainActor
@Suite(.serialized)
struct QuickPlacementRuntimeTests {
    @Test func everyNativeMenuActionPlacesAndPersistsTheRestingCube() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ConfigurationStore(url: directory.appendingPathComponent("settings.json"))
        let model = AppModel(store: store)
        let window = NSPanel(contentRect: CGRect(x: 200, y: 200, width: 100, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { window.orderOut(nil); try? FileManager.default.removeItem(at: directory) }
        window.orderFrontRegardless()
        let controller = CubeHoverController(window: window, settings: CubeHoverSettings(multiplier: 4, delaySeconds: 0), screens: { [CGRect(x: 0, y: 0, width: 1000, height: 800)] })
        controller.onRestingPositionChange = { model.savePosition($0) }
        controller.pointerChanged(to: CGPoint(x: 2000, y: 2000))
        let menu = CubePlacementMenu { controller.place(at: $0) }
        let expected = [CGPoint(x: 24, y: 676), CGPoint(x: 876, y: 676), CGPoint(x: 24, y: 24), CGPoint(x: 876, y: 24), CGPoint(x: 450, y: 350)]
        #expect(menu.items.count == 5)
        for (index, origin) in expected.enumerated() {
            menu.performActionForItem(at: index)
            #expect(window.frame == CGRect(origin: origin, size: CGSize(width: 100, height: 100)))
            #expect(try store.load().windowPosition == WindowPosition(x: origin.x, y: origin.y))
            #expect(model.configuration.groups == CubeConfiguration().groups)
        }
    }

    @Test func placementWhileHoveredOrControlShrunkDoesNotSaveTheEnlargedFrameOrJumpBack() {
        _ = NSApplication.shared
        let window = NSPanel(contentRect: CGRect(x: 200, y: 200, width: 100, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        window.orderFrontRegardless()
        let controller = CubeHoverController(window: window, settings: CubeHoverSettings(multiplier: 4, delaySeconds: 0), screens: { [CGRect(x: 0, y: 0, width: 1000, height: 800)] })
        var saved: [CGPoint] = []
        controller.onRestingPositionChange = { saved.append($0) }
        for control in [false, true] {
            controller.pointerChanged(to: CGPoint(x: window.frame.midX, y: window.frame.midY))
            if control { controller.modifierFlagsChanged([.control]) }
            controller.place(at: .bottomRight)
            controller.pointerChanged(to: CGPoint(x: 2000, y: 2000))
            controller.modifierFlagsChanged([])
            #expect(window.frame == CGRect(x: 876, y: 24, width: 100, height: 100))
            controller.pointerChanged(to: CGPoint(x: 926, y: 74))
            #expect(window.frame.size == CGSize(width: 400, height: 400))
            controller.pointerChanged(to: CGPoint(x: 2000, y: 2000))
            #expect(window.frame == CGRect(x: 876, y: 24, width: 100, height: 100))
        }
        #expect(saved == [CGPoint(x: 876, y: 24), CGPoint(x: 876, y: 24)])
    }

    @Test func placementStaysOnTheRestingScreenAndIgnoresRequestsDuringADrag() {
        _ = NSApplication.shared
        let window = NSPanel(contentRect: CGRect(x: -1000, y: 200, width: 100, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        window.orderFrontRegardless()
        let controller = CubeHoverController(window: window, settings: CubeHoverSettings(multiplier: 4, delaySeconds: 0), screens: { [CGRect(x: 0, y: 40, width: 1440, height: 820), CGRect(x: -1920, y: 0, width: 1920, height: 800)] })
        controller.pointerChanged(to: CGPoint(x: -950, y: 250))
        controller.place(at: .topLeft)
        controller.pointerChanged(to: CGPoint(x: 2000, y: 2000))
        #expect(window.frame == CGRect(x: -1896, y: 676, width: 100, height: 100))
        controller.setInteractionActive(true)
        controller.place(at: .center)
        #expect(window.frame == CGRect(x: -1896, y: 676, width: 100, height: 100))
        controller.setInteractionActive(false)
    }
}
