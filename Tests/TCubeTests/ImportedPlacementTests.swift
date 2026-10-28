import AppKit
import Testing
import CubeCore
@testable import TCube

@MainActor
struct ImportedPlacementTests {
    @Test func scaleRestoreDoesNotSaveAnIntermediateOldPosition() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ConfigurationStore(url: folder.appendingPathComponent("config.json"))
        let model = AppModel(store: store)
        let window = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 100, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        let hover = CubeHoverController(window: window, settings: CubeHoverSettings(delaySeconds: 0), screens: { [NSRect(x: 0, y: 0, width: 1000, height: 1000)] })
        hover.onRestingPositionChange = { model.savePosition($0) }
        model.onChange = {
            let side = 100 * model.configuration.scale
            hover.configure(baseSize: NSSize(width: side, height: side), settings: model.configuration.hover)
        }
        model.onConfigurationRestored = {
            if let position = model.configuration.windowPosition {
                hover.restoreRestingFrame(at: NSPoint(x: position.x, y: position.y))
            }
        }
        var imported = CubeConfiguration()
        imported.scale = 1.5
        imported.windowPosition = WindowPosition(x: 500, y: 600)
        try store.save(imported)
        model.applyPersistedConfiguration(imported)
        #expect(model.configuration.windowPosition == imported.windowPosition)
        #expect(try store.load().windowPosition == imported.windowPosition)
        #expect(hover.restingFrame == NSRect(x: 500, y: 600, width: 150, height: 150))
        model.stopThemeCycle()
    }
}
