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
    var hoverChanged: ((Bool) -> Void)?
    var hoverPointChanged: ((NSPoint) -> Void)?
    var modifierFlagsChanged: ((NSEvent.ModifierFlags, NSPoint?) -> Void)?

    init(cubeView: CubeView) {
        self.cubeView = cubeView
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        updateInteractionHelp(expandsFaces: cubeView.model.configuration.expandsFacesOnClick)
    }
    func updateInteractionHelp(expandsFaces: Bool) {
        let click = expandsFaces ? "单击面展开入口" : "单击图标直接打开"
        setAccessibilityLabel("立方体：按住 Ctrl 恢复原大小，Ctrl 加左键按原大小拖动，滚动旋转，\(click)")
        toolTip = "Ctrl 恢复原大小 · Ctrl＋左键按原大小拖动 · 滚动旋转 · \(click) · 右键设置"
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
    private func updateHover(_ inside: Bool, event: NSEvent? = nil) {
        // Capture screen coordinates before modifier handling can resize/move
        // the panel. The event's old local coordinates would then be stale.
        if let event, let window {
            let point = window.convertPoint(toScreen: event.locationInWindow)
            modifierFlagsChanged?(event.modifierFlags, point)
            if let hoverPointChanged { hoverPointChanged(point) }
            else if let hoverChanged { hoverChanged(inside) }
            else { cubeView.setHovered(inside) }
        } else if let hoverChanged { hoverChanged(inside) }
        else { cubeView.setHovered(inside) }
    }
    override func flagsChanged(with event: NSEvent) { modifierFlagsChanged?(event.modifierFlags, nil) }
    override func mouseEntered(with event: NSEvent) { updateHover(true, event: event) }
    override func mouseMoved(with event: NSEvent) { updateHover(true, event: event) }
    override func mouseExited(with event: NSEvent) { updateHover(false, event: event) }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            beginWindowDrag(with: event, leftButton: true)
        } else {
            let point = window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
            modifierFlagsChanged?(event.modifierFlags, point)
            cubeView.beginPrimaryDrag(atScreenPoint: point)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        modifierFlagsChanged?(event.modifierFlags, nil)
        cubeView.mouseDragged(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        modifierFlagsChanged?(event.modifierFlags, nil)
        cubeView.mouseUp(with: event)
    }
    override func rightMouseDown(with event: NSEvent) {
        beginWindowDrag(with: event, leftButton: event.buttonNumber == 0 && event.modifierFlags.contains(.control))
    }
    override func rightMouseDragged(with event: NSEvent) { cubeView.rightMouseDragged(with: event) }
    override func rightMouseUp(with event: NSEvent) { cubeView.rightMouseUp(with: event) }
    override func scrollWheel(with event: NSEvent) { updateHover(true, event: event); cubeView.scrollWheel(with: event) }
    private func beginWindowDrag(with event: NSEvent, leftButton: Bool) {
        let point = window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        modifierFlagsChanged?(event.modifierFlags, point)
        if leftButton { cubeView.beginPrimaryDrag(atScreenPoint: point, moveOnly: true) }
        else { cubeView.beginSecondaryDrag(atScreenPoint: point) }
        guard let window, window.isVisible else { return }
        let mask: NSEvent.EventTypeMask = leftButton ? [.leftMouseDragged, .leftMouseUp] : [.rightMouseDragged, .rightMouseUp]
        let buttonMask = leftButton ? 1 : 2
        // Track the complete system event stream from the original mouse-down.
        // This avoids relying on subsequent ARView/first-responder drag delivery.
        window.trackEvents(matching: mask, timeout: 0.15, mode: .eventTracking) { [weak self] event, stop in
            guard let self, self.window === window else { stop.pointee = true; return }
            guard let event else {
                if !window.isVisible || NSEvent.pressedMouseButtons & buttonMask == 0 {
                    if leftButton { self.cubeView.cancelPrimaryDrag() }
                    else { self.cubeView.cancelRightDrag() }
                    stop.pointee = true
                }
                return
            }
            self.modifierFlagsChanged?(event.modifierFlags, nil)
            if event.type == .rightMouseUp || event.type == .leftMouseUp {
                if leftButton { self.cubeView.mouseUp(with: event) }
                else { self.cubeView.rightMouseUp(with: event) }
                stop.pointee = true
            } else if leftButton { self.cubeView.mouseDragged(with: event) }
            else { self.cubeView.rightMouseDragged(with: event) }
        }
    }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { updateHover(true); return cubeView.draggingEntered(sender) }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { cubeView.prepareForDragOperation(sender) }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool { cubeView.performDragOperation(sender) }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { updateHover(false) }
    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        guard let window else { updateHover(false); return }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        updateHover(bounds.contains(point))
    }
}
