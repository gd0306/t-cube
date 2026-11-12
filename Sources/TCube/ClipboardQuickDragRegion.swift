import AppKit
import SwiftUI

/// A native drag surface above the title text, excluding the close button.
struct ClipboardQuickDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> ClipboardQuickDragView { ClipboardQuickDragView() }
    func updateNSView(_ nsView: ClipboardQuickDragView, context: Context) {}
}

final class ClipboardQuickDragView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = NSUserInterfaceItemIdentifier("clipboard-quick-drag-region")
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}
