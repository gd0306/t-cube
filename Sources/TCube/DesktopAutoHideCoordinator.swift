import AppKit
import CubeCore

/// Owns temporary presentation only; the hover/placement controller owns saved geometry.
@MainActor
final class DesktopAutoHideCoordinator {
    private weak var panel: NSWindow?
    private let hover: CubeHoverController
    private let settings: DesktopAutoHideSettings
    private let screens: () -> [CGRect]
    private let physicalScreens: (() -> [CGRect])?
    private let pointer: () -> CGPoint
    private let busy: () -> Bool
    private let fullscreen: @MainActor (CGRect) -> Bool
    private let clock: () -> TimeInterval
    private let schedulesPolling: Bool
    private let handle: NSPanel
    private let motionAllowed: @MainActor () -> Bool
    private var animator: EdgeDockAnimator?
    private var dockingImage: NSImage?
    private var transitionGeneration = 0
    private var captureTimeout: Task<Void, Never>?
    private var transitionFrame: CGRect?
    private var transitionCubeFrame: CGRect?
    private(set) var isTransitioning = false
    private var state = DesktopAutoHideState()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastFullscreenCheck: TimeInterval?
    private var cachedFullscreen = false
    private var stopped = false
    private(set) var presentation: DesktopAutoHideState.Presentation = .cube
    var isPolling: Bool { timer != nil }
    var handleIsVisible: Bool { handle.isVisible }
    var userVisible: Bool { state.userVisible }
    var willHide: (() -> Void)?
    var didChangePresentation: (() -> Void)?

    init(panel: NSWindow, hover: CubeHoverController, settings: DesktopAutoHideSettings,
         screens: @escaping () -> [CGRect] = { NSScreen.screens.map(\.visibleFrame) },
         physicalScreens: (() -> [CGRect])? = nil,
         pointer: @escaping () -> CGPoint = { NSEvent.mouseLocation },
         busy: @escaping () -> Bool = { false },
         fullscreen: @escaping @MainActor (CGRect) -> Bool = DesktopFullscreenDetector.isFullscreen,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         schedulesPolling: Bool = true,
         motionAllowed: @escaping @MainActor () -> Bool = {
             !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
         }) {
        self.panel = panel; self.hover = hover; self.settings = settings
        self.screens = screens; self.pointer = pointer; self.busy = busy
        self.physicalScreens = physicalScreens
        self.fullscreen = fullscreen; self.clock = clock; self.schedulesPolling = schedulesPolling
        self.motionAllowed = motionAllowed
        panel.animationBehavior = .none
        handle = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 10, height: 56), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        handle.title = "T-Cube · 展开立方体"
        handle.animationBehavior = .none
        handle.isReleasedWhenClosed = false; handle.isOpaque = false; handle.backgroundColor = .clear
        handle.hasShadow = false; handle.level = .floating; handle.hidesOnDeactivate = false
        handle.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle]
        handle.contentView = EdgeRevealView { [weak self] in self?.reveal() }
    }

    func start() {
        settings.onChange = { [weak self] in self?.configure() }
        if observers.isEmpty {
            for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification] {
                observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshFullscreen() }
                })
            }
        }
        configure()
    }

    private func configure() {
        timer?.invalidate(); timer = nil
        lastFullscreenCheck = nil
        if schedulesPolling, state.userVisible, settings.edgeCollapseEnabled || settings.hideInFullscreen {
            let interval = settings.edgeCollapseEnabled ? 0.25 : 1.0
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = interval / 5
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        tick()
    }

    func refreshFullscreen() { lastFullscreenCheck = nil; tick() }

    func tick() {
        guard !stopped, let panel else { return }
        let now = clock(), occupied = busy()
        let resting = hover.restingFrame
        if settings.hideInFullscreen && state.userVisible {
            if lastFullscreenCheck == nil || now < lastFullscreenCheck! || now - lastFullscreenCheck! >= 2 {
                cachedFullscreen = fullscreen(resting); lastFullscreenCheck = now
            }
        } else { cachedFullscreen = false }
        let frame = settings.edgeCollapseEnabled ? DesktopAutoHideGeometry.handle(resting: resting, screens: screens(), physicalScreens: physicalScreens?()) : nil
        let point = pointer()
        // Keep the reveal area alive while expanded so a stationary pointer on
        // the handle cannot cause repeated collapse/reveal and renderer wakes.
        let inside = panel.isVisible && panel.frame.contains(point) || frame?.contains(point) == true
        let desired = state.update(edgeEnabled: settings.edgeCollapseEnabled, edgeAvailable: frame != nil,
            fullscreen: cachedFullscreen && !occupied, pointerInside: inside, busy: occupied, now: now)
        if desired == .edge, let frame, handle.frame != frame { handle.setFrame(frame, display: true) }
        if isTransitioning && (!motionAllowed() || frame != transitionFrame || resting != transitionCubeFrame || occupied) {
            finishImmediately(as: desired)
            presentation = desired
            return
        }
        guard desired != presentation else { return }
        let previous = presentation
        if desired != .cube { willHide?(); hover.resetHover() }
        presentation = desired
        if motionAllowed(), let frame, desired != .hidden, previous != .hidden,
           let surface = panel.contentView as? CubeSurfaceView {
            transition(to: desired, frame: frame, surface: surface)
            return
        }
        finishImmediately(as: desired)
    }

    private func transition(to desired: DesktopAutoHideState.Presentation, frame: CGRect, surface: CubeSurfaceView) {
        guard let panel else { return }
        transitionGeneration += 1
        let token = transitionGeneration
        captureTimeout?.cancel(); captureTimeout = nil
        transitionFrame = frame
        transitionCubeFrame = hover.restingFrame
        isTransitioning = true
        hover.setPresentationSuspended(true)
        if desired == .edge, dockingImage == nil {
            // A lost/failed GPU snapshot must never leave the UI waiting forever.
            captureTimeout = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                guard let self, self.transitionGeneration == token else { return }
                self.finishImmediately(as: self.presentation)
            }
            surface.captureDockingFrame { [weak self] image in
                MainActor.assumeIsolated {
                    guard let self, self.transitionGeneration == token, !self.stopped else { return }
                    self.captureTimeout?.cancel(); self.captureTimeout = nil
                    guard let image else { self.finishImmediately(as: desired); return }
                    self.dockingImage = image
                    self.animate(to: desired, frame: frame, surface: surface, token: token)
                }
            }
        } else if dockingImage != nil {
            animate(to: desired, frame: frame, surface: surface, token: token)
        } else {
            // A reveal while the initial capture is pending has no visible
            // movement to reverse: the original cube is still in place.
            finishImmediately(as: desired)
        }
        // Keep the original window alive until its image is available.
        if desired == .edge && dockingImage == nil { panel.ignoresMouseEvents = false }
    }

    private func animate(to desired: DesktopAutoHideState.Presentation, frame: CGRect, surface: CubeSurfaceView, token: Int) {
        guard let panel, let image = dockingImage else { finishImmediately(as: desired); return }
        let toEdge = desired == .edge
        if !toEdge {
            surface.retainDockingFrame(image)
            panel.alphaValue = 0.01
            panel.ignoresMouseEvents = true
            panel.orderFrontRegardless()
        }
        handle.alphaValue = 0.01
        handle.orderFrontRegardless()
        (handle.contentView as? EdgeRevealView)?.setPresented(false)
        if animator == nil { animator = EdgeDockAnimator() }
        animator?.animate(image: image, cube: hover.restingFrame, handle: frame, toEdge: toEdge) { [weak self] in
            guard let self, self.transitionGeneration == token, !self.stopped else { return }
            self.settle(as: desired)
        }
        if toEdge { panel.orderOut(nil) }
        didChangePresentation?()
    }

    private func finishImmediately(as desired: DesktopAutoHideState.Presentation) {
        transitionGeneration += 1
        captureTimeout?.cancel(); captureTimeout = nil
        // Settle the real windows before removing the transition's last frame.
        settle(as: desired)
        animator?.cancel()
    }

    private func settle(as desired: DesktopAutoHideState.Presentation) {
        guard let panel else { return }
        isTransitioning = false; transitionFrame = nil; transitionCubeFrame = nil
        panel.alphaValue = 1; handle.alphaValue = 1
        hover.setPresentationSuspended(false)
        switch desired {
        case .cube:
            handle.orderOut(nil)
            panel.ignoresMouseEvents = false
            panel.orderFrontRegardless()
            hover.checkPointer()
        case .edge:
            panel.orderOut(nil); handle.orderFrontRegardless()
        case .hidden:
            panel.orderOut(nil); handle.orderOut(nil)
        }
        if desired != .edge { dockingImage = nil }
        (handle.contentView as? EdgeRevealView)?.setPresented(desired == .edge)
        didChangePresentation?()
    }

    func setUserVisible(_ visible: Bool) { state.setUserVisible(visible); configure() }
    func reveal() { state.reveal(); configure() }

    func stop() {
        transitionGeneration += 1
        captureTimeout?.cancel(); captureTimeout = nil
        animator?.shutdown(); animator = nil
        dockingImage = nil; isTransitioning = false
        panel?.alphaValue = 1; panel?.ignoresMouseEvents = false
        hover.setPresentationSuspended(false)
        stopped = true; timer?.invalidate(); timer = nil
        settings.onChange = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll(); handle.orderOut(nil)
        (handle.contentView as? EdgeRevealView)?.shutdown()
    }
}

/// Reads public window geometry, never titles, screen pixels, or accessibility data.
@MainActor
enum DesktopFullscreenDetector {
    static func isFullscreen(restingFrame: CGRect) -> Bool {
        guard let visible = WindowPlacement.visibleScreen(for: restingFrame, screens: NSScreen.screens.map(\.visibleFrame)),
              let screen = NSScreen.screens.first(where: { $0.visibleFrame == visible }),
              let main = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        return coversDisplay(windows: windows, screen: screen.frame, primaryTop: main.frame.maxY,
            safeTop: screen.safeAreaInsets.top, ownPID: ProcessInfo.processInfo.processIdentifier)
    }

    static func coversDisplay(windows: [[String: Any]], screen: CGRect, primaryTop: CGFloat, safeTop: CGFloat, ownPID: pid_t) -> Bool {
        // CGWindowList is front-to-back. A normal foreground window on this
        // display takes precedence over a fullscreen window behind it.
        for entry in windows {
            guard let owner = entry[kCGWindowOwnerPID as String] as? NSNumber, owner.int32Value != ownPID,
                  (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let raw = entry[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: raw as CFDictionary) else { continue }
            let bounds = CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
            let overlap = bounds.intersection(screen)
            guard !overlap.isNull, overlap.width > 2, overlap.height > 2 else { continue }
            return DesktopAutoHideGeometry.isFullscreen(window: bounds, screen: screen, safeTop: safeTop)
        }
        return false
    }
}
