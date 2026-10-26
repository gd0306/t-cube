import AppKit
import CubeCore

/// The saved resting frame never changes merely because the pointer enters or exits.
@MainActor
final class CubeHoverController {
    private weak var window: NSWindow?
    private var restingFrame: NSRect
    private var settings: CubeHoverSettings
    private let screens: () -> [NSRect]
    private var desiredHovered = false
    private var interactionActive = false
    private var controlHeld = false
    private var controlFrame: NSRect?
    private var lastPointer: NSPoint?
    private var trackingPointer = false
    private var modifierTimer: Timer?
    private var localMotion: Any?
    private var globalMotion: Any?
    private(set) var isHovered = false
    var onHoverChange: ((Bool) -> Void)?
    var onRestingPositionChange: ((NSPoint) -> Void)?

    init(window: NSWindow, settings: CubeHoverSettings, screens: @escaping () -> [NSRect] = { NSScreen.screens.map(\.visibleFrame) }) {
        self.window = window
        restingFrame = window.frame
        self.settings = settings
        self.screens = screens
    }

    func configure(baseSize: NSSize, settings: CubeHoverSettings) {
        let previous = restingFrame
        restingFrame = NSRect(x: previous.midX - baseSize.width / 2, y: previous.midY - baseSize.height / 2, width: baseSize.width, height: baseSize.height)
        restingFrame.origin = WindowPlacement.clamp(restingFrame.origin, size: baseSize, screens: screens())
        self.settings = settings
        controlFrame = nil
        if !interactionActive { applyFrame() }
        if restingFrame.origin != previous.origin { onRestingPositionChange?(restingFrame.origin) }
    }

    func pointerChanged(to point: NSPoint) {
        guard let window else { return }
        lastPointer = point
        desiredHovered = window.isVisible && window.frame.contains(point)
        if !interactionActive { applyHover() }
    }

    func modifierFlagsChanged(_ flags: NSEvent.ModifierFlags, at point: NSPoint? = nil) {
        if let point { lastPointer = point }
        let held = flags.contains(.control)
        guard held != controlHeld else { return }
        if let point, let window { desiredHovered = window.isVisible && window.frame.contains(point) }
        controlHeld = held
        // A drag owns its geometry until mouse-up, even if Control is released.
        if !interactionActive { applyHover() }
    }

    func checkPointer() {
        let point = NSEvent.mouseLocation
        modifierFlagsChanged(NSEvent.modifierFlags, at: point)
        pointerChanged(to: point)
    }

    func setInteractionActive(_ active: Bool) {
        interactionActive = active
        if !active { applyHover() }
        updateModifierTracking()
    }

    func resetHover() {
        desiredHovered = false
        interactionActive = false
        controlHeld = false
        controlFrame = nil
        applyHover()
    }

    func commitMovedFrame(_ frame: NSRect) {
        // Once the user moves an enlarged cube, its actual centre becomes the
        // resting centre. This also avoids a release-time jump near screen edges.
        let origin = NSPoint(x: frame.midX - restingFrame.width / 2, y: frame.midY - restingFrame.height / 2)
        restingFrame.origin = WindowPlacement.clamp(origin, size: restingFrame.size, screens: screens())
        if controlFrame != nil { controlFrame = restingFrame }
        onRestingPositionChange?(restingFrame.origin)
        if !interactionActive { applyFrame() }
    }

    func place(at placement: CubePlacement) {
        guard let window, !interactionActive,
              let screen = WindowPlacement.visibleScreen(for: restingFrame, screens: screens()) else { return }
        restingFrame.origin = WindowPlacement.origin(for: placement, size: restingFrame.size, in: screen)
        controlFrame = nil
        // Start from the resting geometry even if a corner-clamped hover or
        // Control shrink has temporarily moved the visible panel elsewhere.
        window.setFrame(restingFrame, display: true)
        desiredHovered = window.isVisible && restingFrame.contains(lastPointer ?? NSEvent.mouseLocation)
        applyHover()
        onRestingPositionChange?(restingFrame.origin)
    }

    func startTrackingPointer() {
        stopTrackingPointer()
        trackingPointer = true
        let motion: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        localMotion = NSEvent.addLocalMonitorForEvents(matching: motion.union(.flagsChanged)) { [weak self] event in
            if event.type == .flagsChanged {
                self?.modifierFlagsChanged(event.modifierFlags, at: NSEvent.mouseLocation)
                return event
            }
            // The cube input view handles its own event coordinates. Avoid
            // resizing twice while the same mouse event is being dispatched.
            if let self, event.window !== self.window {
                if let source = event.window {
                    let point = source.convertPoint(toScreen: event.locationInWindow)
                    self.modifierFlagsChanged(event.modifierFlags, at: point)
                    self.pointerChanged(to: point)
                } else { self.checkPointer() }
            }
            return event
        }
        globalMotion = NSEvent.addGlobalMonitorForEvents(matching: motion) { [weak self] event in
            MainActor.assumeIsolated {
                let point = NSEvent.mouseLocation
                self?.modifierFlagsChanged(event.modifierFlags, at: point)
                self?.pointerChanged(to: point)
            }
        }
        checkPointer()
    }

    func stopTrackingPointer() {
        trackingPointer = false
        modifierTimer?.invalidate()
        modifierTimer = nil
        if let localMotion { NSEvent.removeMonitor(localMotion) }
        if let globalMotion { NSEvent.removeMonitor(globalMotion) }
        localMotion = nil
        globalMotion = nil
    }

    private func applyHover() {
        let changed = isHovered != desiredHovered
        isHovered = desiredHovered
        applyFrame()
        updateModifierTracking()
        if changed { onHoverChange?(isHovered) }
    }

    private func applyFrame() {
        guard let window else { return }
        if controlHeld && isHovered {
            if controlFrame == nil {
                // Preserve the pointer's relative position while shrinking, so
                // the small cube stays grabbable even at an enlarged corner.
                let point = lastPointer ?? NSPoint(x: window.frame.midX, y: window.frame.midY)
                let u = min(1, max(0, (point.x - window.frame.minX) / window.frame.width))
                let v = min(1, max(0, (point.y - window.frame.minY) / window.frame.height))
                let origin = NSPoint(x: point.x - u * restingFrame.width, y: point.y - v * restingFrame.height)
                controlFrame = NSRect(origin: WindowPlacement.clamp(origin, size: restingFrame.size, screens: screens()), size: restingFrame.size)
            }
            if let controlFrame, window.frame != controlFrame { window.setFrame(controlFrame, display: true) }
            return
        }
        controlFrame = nil
        let factor = isHovered && settings.isEnabled && !controlHeld ? settings.multiplier : 1
        let size = NSSize(width: restingFrame.width * factor, height: restingFrame.height * factor)
        let origin = NSPoint(x: restingFrame.midX - size.width / 2, y: restingFrame.midY - size.height / 2)
        let target = NSRect(origin: WindowPlacement.clamp(origin, size: size, screens: screens()), size: size)
        if window.frame != target { window.setFrame(target, display: true) }
    }

    private func updateModifierTracking() {
        guard trackingPointer && (isHovered || interactionActive) else {
            modifierTimer?.invalidate()
            modifierTimer = nil
            return
        }
        guard modifierTimer == nil else { return }
        // The floating panel need not become key. Reading modifier state also
        // avoids installing a global keyboard monitor or requesting permission.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            MainActor.assumeIsolated {
                self.modifierFlagsChanged(NSEvent.modifierFlags, at: NSEvent.mouseLocation)
            }
        }
        modifierTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }
}
