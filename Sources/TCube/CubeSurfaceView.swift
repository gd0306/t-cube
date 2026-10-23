import AppKit

/// Native input is independent of GPU collision readiness and transparent textures.
@MainActor
final class CubeSurfaceView: NSView {
    let cubeView: CubeView
    let input: CubeInputOverlay

    init(cubeView: CubeView) {
        self.cubeView = cubeView
        input = CubeInputOverlay(cubeView: cubeView)
        super.init(frame: NSRect(origin: .zero, size: CubeTheme.windowSize))
        addSubview(cubeView)
        addSubview(input)
        cubeView.frame = bounds
        input.frame = bounds
        cubeView.autoresizingMask = [.width, .height]
        input.autoresizingMask = [.width, .height]
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(cubeView:)") }
    override var isOpaque: Bool { false }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.ignoresMouseEvents = false
        window?.acceptsMouseMovedEvents = true
    }
}

@MainActor
final class CubeInputOverlay: NSView {
    private unowned let cubeView: CubeView

    init(cubeView: CubeView) {
        self.cubeView = cubeView
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("立方体：右键拖动位置，触控板左右或上下滑动旋转")
        toolTip = "右键拖动位置 · 双指左右／上下旋转 · 右键单击设置"
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(cubeView:)") }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func draw(_ dirtyRect: NSRect) {
        // One alpha byte keeps a clear native input surface eligible for Window
        // Server hit testing. No opaque plate or visual glass fill is drawn.
        NSColor(white: 0, alpha: 1.0 / 255).setFill()
        bounds.fill()
    }
    override func updateTrackingAreas() {
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self))
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { cubeView.setHovered(true) }
    override func mouseMoved(with event: NSEvent) { cubeView.setHovered(true) }
    override func mouseExited(with event: NSEvent) { cubeView.setHovered(false) }
    override func mouseDown(with event: NSEvent) { cubeView.mouseDown(with: event) }
    override func mouseDragged(with event: NSEvent) { cubeView.mouseDragged(with: event) }
    override func mouseUp(with event: NSEvent) { cubeView.mouseUp(with: event) }
    override func rightMouseDown(with event: NSEvent) { cubeView.rightMouseDown(with: event) }
    override func rightMouseDragged(with event: NSEvent) { cubeView.rightMouseDragged(with: event) }
    override func rightMouseUp(with event: NSEvent) { cubeView.rightMouseUp(with: event) }
    override func scrollWheel(with event: NSEvent) { cubeView.scrollWheel(with: event) }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { cubeView.setHovered(true); return cubeView.draggingEntered(sender) }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { cubeView.prepareForDragOperation(sender) }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool { cubeView.performDragOperation(sender) }
}
