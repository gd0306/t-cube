import AppKit
import Testing
@testable import TCube

@MainActor
struct DesktopAutoHideCoordinatorTests {
    @Test func preferencesDefaultOffAndPersistIndependently() throws {
        let name = "TCubeDesktopTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = DesktopAutoHideSettings(defaults: defaults)
        #expect(!settings.edgeCollapseEnabled && !settings.hideInFullscreen)
        settings.setEdgeCollapse(true)
        let reloaded = DesktopAutoHideSettings(defaults: defaults)
        #expect(reloaded.edgeCollapseEnabled && !reloaded.hideInFullscreen)
    }

    @Test func collapseStopsTheCubeWithoutChangingOrSavingRestingCoordinates() throws {
        _ = NSApplication.shared
        let name = "TCubeDesktopTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = DesktopAutoHideSettings(defaults: defaults)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let panel = NSPanel(contentRect: CGRect(x: 24, y: 300, width: 180, height: 180), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        let hover = CubeHoverController(window: panel, settings: .init(), screens: { [screen] })
        let original = hover.restingFrame
        var saves = 0, now = 0.0, fullscreen = false, busy = false
        var pointer = CGPoint(x: 800, y: 800)
        hover.onRestingPositionChange = { _ in saves += 1 }
        let coordinator = DesktopAutoHideCoordinator(panel: panel, hover: hover, settings: settings,
            screens: { [screen] }, pointer: { pointer }, busy: { busy },
            fullscreen: { _ in fullscreen }, clock: { now }, schedulesPolling: false)
        defer { coordinator.stop() }
        coordinator.start()
        #expect(!coordinator.isPolling)
        settings.setEdgeCollapse(true)
        now = 1; coordinator.tick()
        #expect(coordinator.presentation == .edge && !panel.isVisible && coordinator.handleIsVisible)
        #expect(hover.restingFrame == original && saves == 0)
        pointer = CGPoint(x: 5, y: 390)
        coordinator.reveal()
        #expect(panel.isVisible && !coordinator.handleIsVisible)
        now = 2; coordinator.tick(); now = 4; coordinator.tick()
        #expect(coordinator.presentation == .cube)
        busy = true; now = 20; coordinator.tick()
        #expect(coordinator.presentation == .cube)
        busy = false; settings.setHideInFullscreen(true); fullscreen = true
        coordinator.refreshFullscreen()
        #expect(coordinator.presentation == .hidden && !coordinator.handleIsVisible)
        coordinator.setUserVisible(false)
        fullscreen = false; coordinator.refreshFullscreen()
        #expect(coordinator.presentation == .hidden)
        #expect(hover.restingFrame == original && saves == 0)
        settings.setEdgeCollapse(false)
        coordinator.reveal()
        #expect(panel.isVisible && coordinator.presentation == .cube)
    }

    @Test func manualHidingStopsPollingAndShowingDuringFullscreenOverridesIt() throws {
        _ = NSApplication.shared
        let name = "TCubeDesktopTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = DesktopAutoHideSettings(defaults: defaults)
        let panel = NSPanel(contentRect: CGRect(x: 24, y: 300, width: 180, height: 180), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.orderOut(nil) }
        let hover = CubeHoverController(window: panel, settings: .init())
        let coordinator = DesktopAutoHideCoordinator(panel: panel, hover: hover, settings: settings, fullscreen: { _ in true })
        defer { coordinator.stop() }
        coordinator.start()
        #expect(!coordinator.isPolling)
        settings.setHideInFullscreen(true)
        #expect(coordinator.presentation == .hidden && coordinator.isPolling)
        coordinator.setUserVisible(false)
        #expect(!coordinator.isPolling)
        coordinator.reveal()
        #expect(coordinator.presentation == .cube && coordinator.isPolling)
        settings.setHideInFullscreen(false)
        #expect(!coordinator.isPolling)
        coordinator.stop()
        #expect(!coordinator.handleIsVisible)
    }

    @Test func fullscreenIsDisplayLocalAndOnlyUsesTheFrontVisibleForeignWindow() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        func window(_ rect: CGRect, pid: Int) -> [String: Any] {
            [kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: 0,
             kCGWindowBounds as String: rect.dictionaryRepresentation, kCGWindowAlpha as String: 1]
        }
        let fullscreen = window(screen, pid: 11)
        let anotherDisplay = window(CGRect(x: 1440, y: 0, width: 1000, height: 900), pid: 22)
        #expect(DesktopFullscreenDetector.coversDisplay(windows: [anotherDisplay, fullscreen], screen: screen, primaryTop: 900, safeTop: 0, ownPID: 99))
        let overlay = window(CGRect(x: 200, y: 100, width: 600, height: 500), pid: 33)
        #expect(!DesktopFullscreenDetector.coversDisplay(windows: [overlay, fullscreen], screen: screen, primaryTop: 900, safeTop: 0, ownPID: 99))
        #expect(!DesktopFullscreenDetector.coversDisplay(windows: [fullscreen], screen: screen, primaryTop: 900, safeTop: 0, ownPID: 11))
    }

    @Test func repeatedCollapseDetachesRealityKitAndLeavesOneReusableHandle() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = AppModel(store: .init(url: folder.appendingPathComponent("configuration.json")))
        defer { model.stopThemeCycle() }
        let view = CubeView(model: model)
        let surface = CubeSurfaceView(cubeView: view)
        let area = try #require(NSScreen.main?.visibleFrame)
        let frame = CGRect(x: area.minX + 24, y: area.midY - 82, width: 164, height: 164)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.contentView = surface; panel.orderFrontRegardless()
        defer { panel.orderOut(nil); panel.contentView = nil }
        surface.enableRenderingManagement()
        let hover = CubeHoverController(window: panel, settings: .init(), screens: { [area] })
        let settings = DesktopAutoHideSettings(defaults: try #require(UserDefaults(suiteName: folder.lastPathComponent)))
        defer { UserDefaults(suiteName: folder.lastPathComponent)?.removePersistentDomain(forName: folder.lastPathComponent) }
        var now = 0.0
        let coordinator = DesktopAutoHideCoordinator(panel: panel, hover: hover, settings: settings, screens: { [area] },
            pointer: { CGPoint(x: area.maxX - 100, y: area.minY + 100) }, fullscreen: { _ in false }, clock: { now }, schedulesPolling: false,
            motionAllowed: { false })
        defer { coordinator.stop() }
        coordinator.didChangePresentation = { surface.synchronizeRenderingVisibility() }
        coordinator.start(); settings.setEdgeCollapse(true)
        let windows = NSApp.windows.count
        for _ in 0..<30 {
            coordinator.reveal()
            _ = surface.resumeRendering(forInput: true)
            #expect(view.animationUpdatesRunning)
            now += 1; coordinator.tick()
            #expect(coordinator.presentation == .edge && surface.rendererDetached)
            #expect(!view.animationUpdatesRunning && view.superview == nil)
            #expect(hover.restingFrame == frame)
        }
        #expect(NSApp.windows.count == windows)
        coordinator.stop()
        #expect(!coordinator.isPolling && !coordinator.handleIsVisible)
    }
}
