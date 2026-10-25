import AppKit
import Testing
import CubeCore
@testable import TCube

@MainActor
@Suite(.serialized)
struct FaceExpansionTests {
    @Test func outsideClicksCloseTheExpansionButIconAreaClicksDoNot() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(store: ConfigurationStore(url: directory.appendingPathComponent("configuration.json")))
        let controller = FaceExpansionController(model: model)
        let origin = try #require(NSScreen.main?.visibleFrame.origin)
        let source = NSPanel(contentRect: CGRect(x: origin.x + 100, y: origin.y + 100, width: 164, height: 164), styleMask: [.borderless], backing: .buffered, defer: false)
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 164, height: 164))
        source.contentView = view
        source.orderFrontRegardless()
        defer { controller.close(); source.orderOut(nil); try? FileManager.default.removeItem(at: directory) }
        controller.show(face: .front, from: view, rect: CGRect(x: 81, y: 81, width: 2, height: 2))
        let expansion = try #require(NSApp.windows.first { $0.title == "T-Cube · 入口" && $0.isVisible })
        #expect(!controller.dismissIfOutside(expansion))
        #expect(expansion.isVisible)
        #expect(controller.dismissIfOutside(source))
        #expect(!expansion.isVisible)
        // A click in another application has no local NSWindow.
        controller.show(face: .front, from: view, rect: CGRect(x: 81, y: 81, width: 2, height: 2))
        #expect(controller.dismissIfOutside(nil))
        #expect(!expansion.isVisible)
    }
}
