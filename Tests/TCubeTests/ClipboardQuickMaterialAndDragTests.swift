import AppKit
import CubeCore
import Testing
@testable import TCube

@MainActor
struct ClipboardQuickMaterialAndDragTests {
    @Test func headerStartsNativeWindowDraggingWithoutChangingControls() throws {
        _ = NSApplication.shared
        let panel = DragCapturePanel(contentRect: NSRect(x: 100, y: 100, width: 300, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        defer { panel.orderOut(nil) }
        let drag = ClipboardQuickDragView(frame: NSRect(x: 0, y: 0, width: 240, height: 40))
        panel.contentView = drag
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 20, y: 20), modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        drag.mouseDown(with: event)
        #expect(panel.dragEvent === event)
        #expect(drag.acceptsFirstMouse(for: event))
    }

    @Test func panelUsesFrostedMaterialAndAHeaderDragRegionThatExcludesClose() async throws {
        _ = NSApplication.shared
        let board = NSPasteboard(name: .init("TCubeQuickMaterial-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let history = ClipboardHistoryModel(pasteboard: board, schedulesPolling: false)
        let quick = ClipboardQuickController(history: history, copyText: { _ in true }, copyImage: { _ in true }, openManager: {})
        defer { quick.stop(); history.shutdown() }
        quick.show()
        try await Task.sleep(for: .milliseconds(100))
        let panel = try #require(quick.panel)
        let content = try #require(panel.contentView)
        let glass = try #require(content as? NSVisualEffectView)
        #expect(glass.material == .popover)
        #expect(glass.blendingMode == .behindWindow)
        #expect(glass.state == .active)
        #expect(panel.isMovable)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let drag = try #require(descendants(content).first { $0.identifier?.rawValue == "clipboard-quick-drag-region" })
        #expect(drag.bounds.width > 200 && drag.bounds.height > 20)
        let center = drag.convert(NSPoint(x: drag.bounds.midX, y: drag.bounds.midY), to: content)
        #expect(content.hitTest(center) === drag)
        let close = drag.convert(NSPoint(x: drag.bounds.maxX + 20, y: drag.bounds.midY), to: content)
        #expect(content.bounds.contains(close))
        #expect(content.hitTest(close) !== drag)
    }
}

@MainActor
private final class DragCapturePanel: NSPanel {
    var dragEvent: NSEvent?
    override func performDrag(with event: NSEvent) { dragEvent = event }
}
