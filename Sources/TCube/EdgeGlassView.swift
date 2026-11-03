import AppKit
import Combine
import QuartzCore

/// A tiny system material and one compositor animation; no drawing loop or 3D view.
@MainActor
final class EdgeRevealView: NSView {
    private let reveal: () -> Void
    private let motionAllowed: @MainActor () -> Bool
    private let transparencyAllowed: @MainActor () -> Bool
    private let windowVisible: @MainActor (NSWindow) -> Bool
    private let material = NSVisualEffectView()
    private let overlay = NSView()
    private let tint = CAGradientLayer()
    private let gleam = CAGradientLayer()
    private var presented = false
    private var stopped = false
    private var subscriptions: Set<AnyCancellable> = []
    private static let flowKey = "TCube.edgeGlass.flow"

    init(motionAllowed: @escaping @MainActor () -> Bool = {
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }, transparencyAllowed: @escaping @MainActor () -> Bool = {
        !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }, windowVisible: @escaping @MainActor (NSWindow) -> Bool = {
        $0.isVisible && $0.occlusionState.contains(.visible)
    }, reveal: @escaping () -> Void) {
        self.reveal = reveal
        self.motionAllowed = motionAllowed
        self.transparencyAllowed = transparencyAllowed
        self.windowVisible = windowVisible
        super.init(frame: CGRect(x: 0, y: 0, width: 10, height: 56))
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowRadius = 1
        layer?.shadowOpacity = 0.16
        layer?.shadowOffset = CGSize(width: 0, height: -0.5)
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 4
        material.layer?.masksToBounds = true
        addSubview(material)
        overlay.wantsLayer = true
        overlay.layer = tint
        tint.cornerRadius = 4
        tint.masksToBounds = true
        tint.borderWidth = 0.75
        tint.startPoint = CGPoint(x: 0, y: 1)
        tint.endPoint = CGPoint(x: 1, y: 0)
        gleam.name = "Edge glass shimmer"
        gleam.startPoint = CGPoint(x: 0.25, y: 0)
        gleam.endPoint = CGPoint(x: 0.75, y: 1)
        gleam.locations = [0, 0.45, 0.55, 1]
        gleam.shouldRasterize = true
        tint.addSublayer(gleam)
        addSubview(overlay)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("展开立方体")
        toolTip = "展开 T-Cube"
        observe(NotificationCenter.default, NSWindow.didChangeOcclusionStateNotification) { [weak self] notification in
            guard let self, let changed = notification.object as? NSWindow, changed === self.window else { return }
            self.updateFlow()
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { [weak self] _ in
            self?.refreshSystemStyle()
        }
        observe(NotificationCenter.default, .NSProcessInfoPowerStateDidChange) { [weak self] _ in
            self?.refreshSystemStyle()
        }
        refreshSystemStyle()
    }

    required init?(coder: NSCoder) { nil }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping @MainActor (Notification) -> Void) {
        center.publisher(for: name).receive(on: DispatchQueue.main).sink { notification in
            MainActor.assumeIsolated { action(notification) }
        }.store(in: &subscriptions)
    }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let body = bounds.insetBy(dx: 1, dy: 2)
        material.frame = body
        overlay.frame = body
        layer?.shadowPath = CGPath(roundedRect: body, cornerWidth: 4, cornerHeight: 4, transform: nil)
        // Keep layout independent of the static/animated translation transform.
        gleam.bounds = CGRect(x: 0, y: 0, width: body.width, height: 20)
        gleam.position = CGPoint(x: body.width / 2, y: -10)
        gleam.rasterizationScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshSystemStyle()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshSystemStyle()
    }

    func refreshSystemStyle() {
        guard !stopped else { return }
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let translucent = transparencyAllowed()
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> CGColor {
            NSColor(srgbRed: r, green: g, blue: b, alpha: a).cgColor
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        material.isHidden = !translucent
        if dark {
            tint.colors = [color(0.045, 0.060, 0.090, translucent ? 0.80 : 1), color(0.010, 0.015, 0.030, translucent ? 0.88 : 1)]
            tint.borderColor = color(0.66, 0.75, 0.88, 0.40)
            gleam.colors = [color(0.7, 0.85, 1, 0), color(0.72, 0.86, 1, 0.25), color(0.94, 0.98, 1, 0.55), color(0.7, 0.85, 1, 0)]
        } else {
            tint.colors = [color(1, 1, 1, translucent ? 0.60 : 1), color(0.87, 0.91, 0.96, translucent ? 0.68 : 1)]
            tint.borderColor = color(1, 1, 1, 0.90)
            gleam.colors = [color(1, 1, 1, 0), color(1, 1, 1, 0.45), color(1, 1, 1, 0.95), color(1, 1, 1, 0)]
        }
        CATransaction.commit()
        needsLayout = true
        updateFlow()
    }

    func setPresented(_ visible: Bool) {
        presented = visible
        updateFlow()
    }

    private func updateFlow() {
        let visible = !stopped && presented && window.map(windowVisible) == true
        let animated = visible && motionAllowed() && transparencyAllowed()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        gleam.isHidden = !visible
        if animated {
            gleam.transform = CATransform3DIdentity
            if gleam.animation(forKey: Self.flowKey) == nil {
                let flow = CAKeyframeAnimation(keyPath: "transform.translation.y")
                flow.values = [0, 0, 74, 74]
                flow.keyTimes = [0, 0.12, 0.88, 1]
                flow.duration = 8
                flow.preferredFrameRateRange = CAFrameRateRange(minimum: 12, maximum: 30, preferred: 24)
                flow.repeatCount = .infinity
                flow.timingFunctions = [.init(name: .linear), .init(name: .easeInEaseOut), .init(name: .linear)]
                gleam.add(flow, forKey: Self.flowKey)
            }
        } else {
            gleam.removeAnimation(forKey: Self.flowKey)
            gleam.transform = CATransform3DMakeTranslation(0, 36, 0)
        }
        CATransaction.commit()
    }

    func shutdown() {
        stopped = true; presented = false
        subscriptions.removeAll()
        updateFlow()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { reveal() }
    override func mouseDown(with event: NSEvent) { reveal() }
    override func accessibilityPerformPress() -> Bool { reveal(); return true }
}
