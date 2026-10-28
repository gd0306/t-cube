import AppKit

/// Native input is independent of GPU collision readiness and transparent textures.
@MainActor
final class CubeSurfaceView: NSView {
    let cubeView: CubeView
    let input: CubeInputOverlay
    var contentRequested: (() -> Void)?
    var contentCaptureRequested: ((String) -> Void)?
    private let contentButton = NSButton()
    private let frozenImage = NSImageView()
    private var visibilityObserver: NSObjectProtocol?
    private var snapshotGeneration = 0
    private var snapshotPending = false
    private(set) var rendererDetached = false
    private var managesRendering = false
    var hasFrozenFrame: Bool { !frozenImage.isHidden && frozenImage.image != nil }

    func enableRenderingManagement() {
        guard !managesRendering else { return }
        managesRendering = true
        cubeView.renderingRequested = { [weak self] in self?.resumeRendering() ?? false }
        cubeView.staticFrameRequested = { [weak self] in self?.freezeStaticFrame() }
        input.renderingRequested = { [weak self] in _ = self?.resumeRendering(forInput: true) }
        observeRenderingWindow()
    }

    @discardableResult
    func resumeRendering(forInput: Bool = false) -> Bool {
        guard managesRendering else { cubeView.resumeAnimationUpdates(); return true }
        guard let window, window.isVisible,
              forInput || cubeView.superview === self || window.occlusionState.contains(.visible) else { return false }
        snapshotGeneration += 1
        snapshotPending = false
        if cubeView.superview !== self {
            cubeView.frame = bounds
            addSubview(cubeView, positioned: .below, relativeTo: input)
        }
        frozenImage.isHidden = true
        rendererDetached = false
        cubeView.resumeAnimationUpdates()
        return true
    }

    func synchronizeRenderingVisibility() {
        guard managesRendering else { return }
        if window?.isVisible == true, window?.occlusionState.contains(.visible) == true {
            _ = resumeRendering()
        } else {
            snapshotGeneration += 1
            snapshotPending = false
            cubeView.suspendAnimationUpdates()
            cubeView.removeFromSuperview()
            rendererDetached = true
        }
    }

    private func freezeStaticFrame() {
        guard !snapshotPending, cubeView.superview === self, window?.isVisible == true else { return }
        snapshotPending = true
        snapshotGeneration += 1
        let generation = snapshotGeneration
        cubeView.snapshot(saveToHDR: false) { [weak self] image in
            MainActor.assumeIsolated {
                guard let self, self.snapshotGeneration == generation else { return }
                self.snapshotPending = false
                guard let image else { self.cubeView.suspendAnimationUpdates(); return }
                self.frozenImage.image = image
                self.frozenImage.frame = self.bounds
                self.frozenImage.isHidden = false
                self.cubeView.suspendAnimationUpdates()
                self.cubeView.removeFromSuperview()
                self.rendererDetached = true
            }
        }
    }

    func setContentButtonVisible(_ visible: Bool) { contentButton.isHidden = !visible }
    @objc private func openContent() { contentRequested?() }

    init(cubeView: CubeView) {
        self.cubeView = cubeView
        input = CubeInputOverlay(cubeView: cubeView)
        super.init(frame: NSRect(origin: .zero, size: CubeTheme.windowSize))
        frozenImage.imageScaling = .scaleAxesIndependently
        frozenImage.autoresizingMask = [.width, .height]
        frozenImage.isHidden = true
        addSubview(frozenImage)
        addSubview(cubeView)
        addSubview(input)
        input.textDropRequested = { [weak self] text in self?.contentCaptureRequested?(text) }
        cubeView.frame = bounds
        input.frame = bounds
        cubeView.autoresizingMask = [.width, .height]
        input.autoresizingMask = [.width, .height]
        contentButton.image = NSImage(systemSymbolName: "text.badge.plus", accessibilityDescription: "常用内容")
        contentButton.bezelStyle = .rounded
        contentButton.toolTip = "常用内容 · ⌘⇧Space"
        contentButton.setAccessibilityLabel("打开常用内容库")
        contentButton.target = self
        contentButton.action = #selector(openContent)
        contentButton.frame = NSRect(x: bounds.width - 38, y: 4, width: 32, height: 26)
        contentButton.autoresizingMask = [.minXMargin, .maxYMargin]
        contentButton.isHidden = true
        addSubview(contentButton)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(cubeView:)") }
    override var isOpaque: Bool { false }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.ignoresMouseEvents = false
        window?.acceptsMouseMovedEvents = true
        observeRenderingWindow()
    }

    private func observeRenderingWindow() {
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = nil
        guard managesRendering else { return }
        if let window {
            visibilityObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.synchronizeRenderingVisibility() }
            }
        }
        synchronizeRenderingVisibility()
    }
}

@MainActor
final class CubeInputOverlay: NSView {
    private unowned let cubeView: CubeView
    var renderingRequested: (() -> Void)?
    private var clickFeedback: NSPoint?
    private var feedbackGeneration = 0

    private func showClickFeedback(at point: NSPoint) {
        clickFeedback = point
        feedbackGeneration += 1
        let generation = feedbackGeneration
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, self.feedbackGeneration == generation else { return }
            self.clickFeedback = nil
            self.needsDisplay = true
        }
    }

    var hoverChanged: ((Bool) -> Void)?
    var textDropRequested: ((String) -> Void)?
    var hoverPointChanged: ((NSPoint) -> Void)?
    var modifierFlagsChanged: ((NSEvent.ModifierFlags, NSPoint?) -> Void)?

    init(cubeView: CubeView) {
        self.cubeView = cubeView
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL, .string])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        updateInteractionHelp(expandsFaces: cubeView.model.configuration.expandsFacesOnClick)
    }
    func updateInteractionHelp(expandsFaces: Bool) {
        let click = expandsFaces ? "单击面展开入口" : "单击图标直接打开"
        setAccessibilityLabel("立方体：左键拖动位置，右键拖动旋转，按住 Ctrl 恢复原大小，Ctrl 加左键按原大小拖动，滚动旋转，\(click)")
        toolTip = "左键拖动位置 · 右键拖动旋转 · Ctrl 恢复原大小 · Ctrl＋左键按原大小拖动 · 滚动旋转 · \(click) · 右键设置"
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
        if let point = clickFeedback {
            NSColor.controlAccentColor.withAlphaComponent(0.65).setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20))
            ring.lineWidth = 2
            ring.stroke()
        }
    }
    override func updateTrackingAreas() {
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self))
        super.updateTrackingAreas()
    }
    private func updateHover(_ inside: Bool, event: NSEvent? = nil) {
        if inside { renderingRequested?() }
        // Capture screen coordinates before modifier handling can resize/move
        // the panel. The event's old local coordinates would then be stale.
        if let event, let window {
            let point = window.convertPoint(toScreen: event.locationInWindow)
            modifierFlagsChanged?(event.modifierFlags, point)
            if let hoverPointChanged { hoverPointChanged(point) }
            else if let hoverChanged { hoverChanged(inside) }
            else { cubeView.setHovered(inside) }
            // Hover callbacks may resize the window; convert the captured screen
            // point only after they finish, rather than using stale event coordinates.
            cubeView.updateSlimePointer(atWindowPoint: inside ? window.convertPoint(fromScreen: point) : nil)
        } else if let hoverChanged { hoverChanged(inside) }
        else { cubeView.setHovered(inside) }
        if !inside { cubeView.updateSlimePointer(atWindowPoint: nil) }
    }
    override func flagsChanged(with event: NSEvent) { modifierFlagsChanged?(event.modifierFlags, nil) }
    override func mouseEntered(with event: NSEvent) { updateHover(true, event: event) }
    override func mouseMoved(with event: NSEvent) { updateHover(true, event: event) }
    override func mouseExited(with event: NSEvent) { updateHover(false, event: event) }
    override func mouseDown(with event: NSEvent) {
        renderingRequested?()
        showClickFeedback(at: convert(event.locationInWindow, from: nil))
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
        renderingRequested?()
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
    private func droppedText(_ sender: any NSDraggingInfo) -> String? {
        guard sender.draggingPasteboard.availableType(from: [.fileURL]) == nil,
            let text = sender.draggingPasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updateHover(true)
        return droppedText(sender) != nil ? .copy : cubeView.draggingEntered(sender)
    }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { droppedText(sender) != nil || cubeView.prepareForDragOperation(sender) }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if let text = droppedText(sender), let textDropRequested { textDropRequested(text); return true }
        return cubeView.performDragOperation(sender)
    }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { updateHover(false) }
    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        guard let window else { updateHover(false); return }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        updateHover(bounds.contains(point))
    }
}
