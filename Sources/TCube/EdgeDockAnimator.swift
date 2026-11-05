import AppKit
import QuartzCore

/// A single reusable, input-transparent window. Only the compositor moves pixels;
/// the real cube's geometry and the user's saved position never participate.
@MainActor
final class EdgeDockAnimator {
    private let window: NSPanel
    private let imageLayer = CALayer()
    private let glass = EdgeRevealView(motionAllowed: { false }, reveal: {})
    private var completion: (() -> Void)?
    private var generation = 0
    var isRunning: Bool { completion != nil }

    init() {
        window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "T-Cube · 贴边过渡"
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.level = .floating; window.hidesOnDeactivate = false; window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle]
        let view = NSView()
        view.wantsLayer = true
        window.contentView = view
        imageLayer.contentsGravity = .resize
        imageLayer.allowsEdgeAntialiasing = true
        view.layer?.addSublayer(imageLayer)
        view.addSubview(glass)
    }

    func animate(image: NSImage, cube: CGRect, handle: CGRect, toEdge: Bool, completion: @escaping () -> Void) {
        // Sampling the presentation layer makes reversal start at the pixels the
        // user currently sees, rather than at the previous animation's endpoint.
        let current = isRunning ? imageLayer.presentation() : nil
        let currentFrame = current?.frame.offsetBy(dx: window.frame.minX, dy: window.frame.minY)
        let currentOpacity = current?.opacity
        let glassOpacity = isRunning ? glass.layer?.presentation()?.opacity : nil
        let glassTransform = isRunning ? glass.layer?.presentation()?.transform : nil
        generation += 1
        let token = generation
        self.completion = completion
        let frame = cube.union(handle).insetBy(dx: -24, dy: -24)
        window.setFrame(frame, display: true)
        window.contentView?.frame = CGRect(origin: .zero, size: frame.size)
        func local(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: -frame.minX, dy: -frame.minY) }
        let direction: CGFloat = handle.midX < cube.midX ? -1 : 1
        func body(_ scaleX: CGFloat, _ scaleY: CGFloat, _ travel: CGFloat) -> CGRect {
            let center = CGPoint(x: cube.midX + (handle.midX - cube.midX) * travel,
                                 y: cube.midY + (handle.midY - cube.midY) * travel)
            return CGRect(x: center.x - cube.width * scaleX / 2, y: center.y - cube.height * scaleY / 2,
                          width: cube.width * scaleX, height: cube.height * scaleY)
        }
        let frames: [CGRect]
        let alphas: [Float]
        if toEdge {
            frames = [currentFrame ?? cube, body(1.08, 0.88, 0.14), body(0.64, 0.72, 0.62),
                      handle.insetBy(dx: -3, dy: -2), handle]
            alphas = [currentOpacity ?? 1, 1, 0.94, 0.28, 0]
        } else {
            frames = [currentFrame ?? handle, handle.insetBy(dx: -4, dy: -3), body(0.83, 0.91, 0.16),
                      cube.insetBy(dx: -cube.width * 0.008, dy: cube.height * 0.004).offsetBy(dx: -direction * 1.5, dy: 0), cube]
            alphas = [currentOpacity ?? 0, max(currentOpacity ?? 0, 0.24), 1, 1, 1]
        }
        let duration = toEdge ? 0.36 : 0.46
        // Interpolate once before submitting to Core Animation. Bounded Hermite
        // tangents avoid both pauses at keyframes and negative/overshooting sizes.
        func samples(_ values: [CGFloat]) -> [CGFloat] {
            let times: [CGFloat] = [0, 0.22, 0.52, 0.80, 1]
            let slopes = (0..<4).map { (values[$0 + 1] - values[$0]) / (times[$0 + 1] - times[$0]) }
            var tangents = [CGFloat](repeating: 0, count: 5)
            for index in 1..<4 where slopes[index - 1] * slopes[index] > 0 {
                tangents[index] = 2 / (1 / slopes[index - 1] + 1 / slopes[index])
            }
            return (0...60).map { index in
                let time = CGFloat(index) / 60
                let segment = min(3, times.dropFirst().prefix(while: { $0 < time }).count)
                let length = times[segment + 1] - times[segment]
                let t = (time - times[segment]) / length
                let t2 = t * t, t3 = t2 * t
                return (2 * t3 - 3 * t2 + 1) * values[segment]
                    + (t3 - 2 * t2 + t) * length * tangents[segment]
                    + (-2 * t3 + 3 * t2) * values[segment + 1]
                    + (t3 - t2) * length * tangents[segment + 1]
            }
        }
        func keyframes(_ key: String, _ values: [Any]) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: key)
            animation.values = values
            animation.calculationMode = .linear
            return animation
        }
        let rects = frames.map(local)
        let xs = samples(rects.map(\.midX)), ys = samples(rects.map(\.midY))
        let widths = samples(rects.map(\.width)), heights = samples(rects.map(\.height))
        let positions = xs.indices.map { NSValue(point: CGPoint(x: xs[$0], y: ys[$0])) }
        let sizes = widths.indices.map { NSValue(rect: CGRect(x: 0, y: 0, width: widths[$0], height: heights[$0])) }
        let imageAnimations = [keyframes("position", positions), keyframes("bounds", sizes), keyframes("opacity", samples(alphas.map(CGFloat.init)))]
        let startGlass = glassTransform ?? CATransform3DMakeScale(toEdge ? 0.25 : 1, toEdge ? 0.7 : 1, 1)
        let transforms = toEdge
            ? [startGlass, CATransform3DMakeScale(0.3, 0.8, 1), CATransform3DMakeScale(0.6, 1.1, 1), CATransform3DMakeScale(1.12, 1.03, 1), CATransform3DIdentity]
            : [startGlass, CATransform3DMakeScale(1.35, 1.08, 1), CATransform3DMakeScale(0.8, 0.7, 1), CATransform3DMakeScale(0.3, 0.6, 1), CATransform3DMakeScale(0.2, 0.6, 1)]
        let glassAlphas: [Float] = toEdge ? [glassOpacity ?? 0, 0, 0.15, 0.85, 1] : [glassOpacity ?? 1, 0.9, 0.2, 0, 0]
        let scaleXs = samples(transforms.map(\.m11)), scaleYs = samples(transforms.map(\.m22))
        let scales = scaleXs.indices.map { NSValue(caTransform3D: CATransform3DMakeScale(scaleXs[$0], scaleYs[$0], 1)) }
        let glassAnimations = [keyframes("transform", scales), keyframes("opacity", samples(glassAlphas.map(CGFloat.init)))]
        CATransaction.begin(); CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == token, let finished = self.completion else { return }
                self.completion = nil
                finished()
                guard self.generation == token else { return }
                self.clear()
            }
        }
        imageLayer.removeAllAnimations(); glass.layer?.removeAllAnimations()
        imageLayer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        imageLayer.frame = local(toEdge ? handle : cube)
        imageLayer.opacity = toEdge ? 0 : 1
        glass.frame = local(handle)
        glass.layoutSubtreeIfNeeded()
        glass.layer?.opacity = toEdge ? 1 : 0
        glass.layer?.transform = transforms.last!
        for (layer, animations) in [(imageLayer, imageAnimations), (glass.layer!, glassAnimations)] {
            let group = CAAnimationGroup()
            group.animations = animations; group.duration = duration
            group.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
            layer.add(group, forKey: "TCube.edgeDock")
        }
        CATransaction.commit()
        window.orderFrontRegardless()
    }

    func cancel() {
        generation += 1
        completion = nil
        clear()
    }

    func shutdown() {
        cancel()
        glass.shutdown()
        window.contentView = nil
        window.close()
    }

    private func clear() {
        window.orderOut(nil)
        imageLayer.removeAllAnimations(); imageLayer.contents = nil
        glass.layer?.removeAllAnimations()
    }
}
