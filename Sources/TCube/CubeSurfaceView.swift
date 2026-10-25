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
    private var controlDrag = false

    init(cubeView: CubeView) {
        self.cubeView = cubeView
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("立方体：按住拖动位置，滚动旋转，单击面展开入口")
        toolTip = "左键或右键按住拖动位置 · 滚动旋转 · 单击面立即展开 · 右键单击设置"
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
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            controlDrag = true
            beginWindowDrag(with: event, leftButton: true)
        } else { cubeView.mouseDown(with: event) }
    }
    override func mouseDragged(with event: NSEvent) {
        if controlDrag { cubeView.rightMouseDragged(with: event) }
        else { cubeView.mouseDragged(with: event) }
    }
    override func mouseUp(with event: NSEvent) {
        if controlDrag { controlDrag = false; cubeView.rightMouseUp(with: event) }
        else { cubeView.mouseUp(with: event) }
    }
    override func rightMouseDown(with event: NSEvent) {
        controlDrag = false
        beginWindowDrag(with: event, leftButton: false)
    }
    override func rightMouseDragged(with event: NSEvent) { cubeView.rightMouseDragged(with: event) }
    override func rightMouseUp(with event: NSEvent) { cubeView.rightMouseUp(with: event) }
    override func scrollWheel(with event: NSEvent) { cubeView.scrollWheel(with: event) }
    private func beginWindowDrag(with event: NSEvent, leftButton: Bool) {
        cubeView.rightMouseDown(with: event)
        guard let window, window.isVisible else { return }
        let mask: NSEvent.EventTypeMask = leftButton ? [.leftMouseDragged, .leftMouseUp] : [.rightMouseDragged, .rightMouseUp]
        let buttonMask = leftButton ? 1 : 2
        // Track the complete system event stream from the original mouse-down.
        // This avoids relying on subsequent ARView/first-responder drag delivery.
        window.trackEvents(matching: mask, timeout: 0.15, mode: .eventTracking) { [weak self] event, stop in
            guard let self, self.window === window else { stop.pointee = true; return }
            guard let event else {
                if !window.isVisible || NSEvent.pressedMouseButtons & buttonMask == 0 {
                    self.cubeView.cancelRightDrag()
                    self.controlDrag = false
                    stop.pointee = true
                }
                return
            }
            if event.type == .rightMouseUp || event.type == .leftMouseUp {
                self.cubeView.rightMouseUp(with: event)
                self.controlDrag = false
                stop.pointee = true
            } else { self.cubeView.rightMouseDragged(with: event) }
        }
    }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { cubeView.setHovered(true); return cubeView.draggingEntered(sender) }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { cubeView.prepareForDragOperation(sender) }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool { cubeView.performDragOperation(sender) }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { cubeView.setHovered(false) }
    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        guard let window else { cubeView.setHovered(false); return }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        cubeView.setHovered(bounds.contains(point))
    }
}
