import AppKit
import CubeCore
import Testing
@testable import TCube

@MainActor
@Suite(.serialized)
struct DesktopPlacementCoordinatorTests {
    @Test func disconnectResizeAndReconnectNeverSaveFallbackOverExternalMemory() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DesktopPositionStore(url: directory.appendingPathComponent("desktop-positions.json"))
        let primary = DesktopDisplay(id: "primary", visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let external = DesktopDisplay(id: "external", visibleFrame: CGRect(x: -1200, y: 0, width: 1200, height: 900))
        let fixture = DisplayFixture([primary, external])
        let panel = NSPanel(contentRect: CGRect(x: -650, y: 400, width: 100, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { panel.orderOut(nil) }
        let hover = CubeHoverController(window: panel, settings: CubeHoverSettings(delaySeconds: 0), screens: { fixture.displays.map(\.visibleFrame) })
        let coordinator = try DesktopPlacementCoordinator(hoverController: hover, panel: panel, store: store, screens: { fixture.displays })
        var saves = 0
        hover.onRestingPositionChange = { _ in saves += 1 }
        hover.onRestingFrameCommitted = { try? coordinator.recordRestingPosition() }
        fixture.displays = [primary]
        coordinator.screenTopologyChanged()
        #expect(hover.restingFrame == CGRect(x: 450, y: 350, width: 100, height: 100))
        hover.configure(baseSize: CGSize(width: 200, height: 200), settings: CubeHoverSettings(delaySeconds: 0))
        fixture.displays = [primary, external]
        coordinator.screenTopologyChanged()
        #expect(hover.restingFrame == CGRect(x: -700, y: 350, width: 200, height: 200))
        #expect(try store.load().preferredDisplayID == "external")
        #expect(saves == 1) // Only the explicit size edit changed legacy placement.
        hover.commitMovedFrame(CGRect(x: 200, y: 200, width: 200, height: 200))
        #expect(try store.load().preferredDisplayID == "primary")
        #expect(try store.load().positions.count == 2)
    }

    @Test func corruptStoreIsPreservedInsteadOfReplacedByInitialFrame() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = DesktopPositionStore(url: directory.appendingPathComponent("desktop-positions.json"))
        try Data("broken".utf8).write(to: store.url)
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        let hover = CubeHoverController(window: panel, settings: CubeHoverSettings())
        #expect(throws: (any Error).self) { try DesktopPlacementCoordinator(hoverController: hover, panel: panel, store: store) }
        #expect(try String(contentsOf: store.url, encoding: .utf8) == "broken")
    }
}

@MainActor
private final class DisplayFixture {
    var displays: [DesktopDisplay]
    init(_ displays: [DesktopDisplay]) { self.displays = displays }
}
