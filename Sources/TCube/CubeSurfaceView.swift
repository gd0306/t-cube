import AppKit

/// Native input remains available while optical frames are prepared offscreen.
@MainActor
final class CubeSurfaceView: NSView {
    let cubeView: CubeView
    let input: CubeInputOverlay
    var contentCaptureRequested: ((String) -> Void)?
    private let frozenImage = NSImageView()
    private let frameCapture: ((@escaping (NSImage?) -> Void) -> Void)?
    private var visibilityObserver: NSObjectProtocol?
    private var snapshotGeneration = 0
    private var snapshotPending = false
    private var managesRendering = false
    private var applyingAppearance = false
    private var preparingTheme = false
    private var pendingAppearance: (() -> Void)?
    private var transitionTask: Task<Void, Never>?
    private(set) var rendererDetached = false
    var hasFrozenFrame: Bool { !frozenImage.isHidden && frozenImage.image != nil }
    var isThemeTransitioning: Bool { preparingTheme || transitionTask != nil || cubeView.presentationTransitionActive }

    func enableRenderingManagement() {
        guard !managesRendering else { return }
        managesRendering = true
        cubeView.renderingRequested = { [weak self] in self?.resumeRendering() ?? false }
        cubeView.staticFrameRequested = { [weak self] in self?.freezeStaticFrame() }
        cubeView.appearanceTransitionRequested = { [weak self] apply in
            if let self { self.prepareAppearance(apply) } else { apply() }
        }
        input.renderingRequested = { [weak self] in _ = self?.resumeRendering(forInput: true) }
        observeRenderingWindow()
    }

    private func invalidatePresentation() {
        snapshotGeneration += 1
        snapshotPending = false
        preparingTheme = false
        transitionTask?.cancel()
        transitionTask = nil
        cubeView.presentationTransitionActive = false
    }

    @discardableResult
    func resumeRendering(forInput: Bool = false) -> Bool {
        guard managesRendering else { cubeView.resumeAnimationUpdates(); return true }
        guard let window, window.isVisible,
              forInput || cubeView.superview === self || window.occlusionState.contains(.visible) else { return false }
        if !applyingAppearance {
            let pending = pendingAppearance
            pendingAppearance = nil
            invalidatePresentation()
            if let pending {
                applyingAppearance = true
                pending()
                applyingAppearance = false
            }
        }
        let retainFrame = hasFrozenFrame && !forInput
        cubeView.alphaValue = retainFrame ? 0 : 1
        if cubeView.superview !== self {
            cubeView.frame = bounds
            addSubview(cubeView, positioned: .below, relativeTo: frozenImage)
        }
        frozenImage.isHidden = !retainFrame
        if !retainFrame { frozenImage.image = nil }
        rendererDetached = false
        cubeView.resumeAnimationUpdates()
        if !forInput && !applyingAppearance {
            let generation = snapshotGeneration
            cubeView.afterPreparedFrames { [weak self] in
                guard let self, self.snapshotGeneration == generation, !self.preparingTheme else { return }
                if self.cubeView.requiresContinuousRendering { self.revealLiveFrame() }
                else { self.captureStaticFrame(generation: generation, resumeAfterTransition: false) }
            }
        }
        return true
    }

    private func revealLiveFrame() {
        cubeView.presentationTransitionActive = false
        cubeView.alphaValue = 1
        frozenImage.isHidden = true
        frozenImage.image = nil
    }

    func synchronizeRenderingVisibility() {
        guard managesRendering else { return }
        if window?.isVisible == true, window?.occlusionState.contains(.visible) == true {
            if !isThemeTransitioning { _ = resumeRendering() }
        } else {
            let pending = pendingAppearance
            pendingAppearance = nil
            invalidatePresentation()
            if let pending { applyingAppearance = true; pending(); applyingAppearance = false }
            cubeView.suspendAnimationUpdates()
            cubeView.removeFromSuperview()
            rendererDetached = true
        }
    }

    private func prepareAppearance(_ apply: @escaping () -> Void) {
        guard window?.isVisible == true, cubeView.superview === self || hasFrozenFrame else {
            applyingAppearance = true; apply(); applyingAppearance = false
            return
        }
        invalidatePresentation()
        preparingTheme = true
        pendingAppearance = apply
        cubeView.presentationTransitionActive = true
        let generation = snapshotGeneration
        if let old = hasFrozenFrame ? frozenImage.image : nil {
            prepareTarget(from: old, generation: generation)
        } else {
            captureFrame { [weak self] old in
                MainActor.assumeIsolated {
                    guard let self, self.snapshotGeneration == generation else { return }
                    self.prepareTarget(from: old, generation: generation)
                }
            }
        }
    }

    private func prepareTarget(from old: NSImage?, generation: Int) {
        guard let apply = pendingAppearance else { return }
        pendingAppearance = nil
        frozenImage.image = old
        frozenImage.isHidden = old == nil
        applyingAppearance = true
        apply()
        applyingAppearance = false
        cubeView.presentationTransitionActive = true
        // A transparent ARView still produces snapshots, but cannot add highlights
        // behind the old transparent image during material/texture preparation.
        cubeView.alphaValue = 0
        cubeView.afterPreparedFrames { [weak self] in
            guard let self, self.snapshotGeneration == generation else { return }
            self.captureStaticFrame(generation: generation, resumeAfterTransition: self.cubeView.requiresContinuousRendering)
        }
    }

    private func captureFrame(_ completion: @escaping (NSImage?) -> Void) {
        if let frameCapture { frameCapture(completion) }
        else { cubeView.snapshot(saveToHDR: false, completion: completion) }
    }

    private func freezeStaticFrame() {
        guard !preparingTheme, !snapshotPending, cubeView.superview === self, window?.isVisible == true else { return }
        snapshotGeneration += 1
        captureStaticFrame(generation: snapshotGeneration, resumeAfterTransition: false)
    }

    private func captureStaticFrame(generation: Int, resumeAfterTransition: Bool) {
        snapshotPending = true
        captureFrame { [weak self] image in
            MainActor.assumeIsolated {
                guard let self, self.snapshotGeneration == generation else { return }
                self.snapshotPending = false
                self.preparingTheme = false
                guard let image else {
                    // A failed snapshot must never remove the only usable surface.
                    self.revealLiveFrame()
                    if self.cubeView.requiresContinuousRendering { self.cubeView.resumeAnimationUpdates() }
                    else { self.cubeView.suspendAnimationUpdates() }
                    return
                }
                self.cubeView.suspendAnimationUpdates()
                self.cubeView.removeFromSuperview()
                self.rendererDetached = true
                self.present(image, generation: generation, resumeAfterTransition: resumeAfterTransition)
            }
        }
    }

    private func present(_ image: NSImage, generation: Int, resumeAfterTransition: Bool) {
        let old = hasFrozenFrame ? frozenImage.image : nil
        frozenImage.frame = bounds
        frozenImage.isHidden = false
        guard let old, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            frozenImage.image = image
            finishPresentation(generation: generation, resumeLive: resumeAfterTransition)
            return
        }
        let blend = ThemeFrameBlend.Prepared(from: old, to: image)
        transitionTask = Task { [weak self] in
            let started = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                guard let self, self.snapshotGeneration == generation else { return }
                let progress = min(1, (ProcessInfo.processInfo.systemUptime - started) / ThemeFrameBlend.duration)
                self.frozenImage.image = blend?.image(progress: progress) ?? image
                if progress == 1 {
                    self.transitionTask = nil
                    self.finishPresentation(generation: generation, resumeLive: resumeAfterTransition)
                    return
                }
                do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
            }
        }
    }

    private func finishPresentation(generation: Int, resumeLive: Bool) {
        guard snapshotGeneration == generation else { return }
        cubeView.presentationTransitionActive = false
        if resumeLive, window?.isVisible == true {
            // Warm the live surface behind the final image before revealing it.
            applyingAppearance = true
            _ = resumeRendering()
            applyingAppearance = false
            cubeView.presentationTransitionActive = true
            cubeView.afterPreparedFrames { [weak self] in
                guard let self, self.snapshotGeneration == generation else { return }
                self.revealLiveFrame()
            }
        }
    }

    init(cubeView: CubeView, frameCapture: ((@escaping (NSImage?) -> Void) -> Void)? = nil) {
        self.cubeView = cubeView
        self.frameCapture = frameCapture
        input = CubeInputOverlay(cubeView: cubeView)
        super.init(frame: NSRect(origin: .zero, size: CubeTheme.windowSize))
        frozenImage.imageScaling = .scaleAxesIndependently
        frozenImage.autoresizingMask = [.width, .height]
        frozenImage.isHidden = true
        addSubview(cubeView)
        addSubview(frozenImage)
        addSubview(input)
        input.textDropRequested = { [weak self] text in self?.contentCaptureRequested?(text) }
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
