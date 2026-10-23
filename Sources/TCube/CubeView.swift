import AppKit
import RealityKit
import CubeCore
import simd

@MainActor
final class CubeView: ARView {
    let model: AppModel
    let cube = Entity()
    private let anchor = AnchorEntity(world: .zero)
    private var panels: [CubeFace: ModelEntity] = [:]
    private var aura: CubeAura!
    private var leftTracker = PointerDragTracker()
    private var rightTracker = PointerDragTracker()
    private var rotation = CubeRotation.snapped(to: .front)
    private var panelOrigin = NSPoint.zero
    private var isSnapping = false
    private var snapTask: Task<Void, Never>?
    private var scrollEndTask: Task<Void, Never>?
    private var isScrolling = false
    private(set) var isHovered = false
    var editRequested: (() -> Void)?

    init(model: AppModel) {
        self.model = model
        super.init(frame: NSRect(origin: .zero, size: CubeTheme.windowSize))
        environment.background = .color(.clear)
        wantsLayer = true
        layer?.isOpaque = false
        scene.addAnchor(anchor)
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 32
        camera.position = [0, 0, 3.45]
        anchor.addChild(camera)
        let key = DirectionalLight()
        key.light.intensity = 1600
        key.look(at: .zero, from: [-2, 4, 4], relativeTo: nil)
        anchor.addChild(key)
        let fill = DirectionalLight()
        fill.light.intensity = 450
        fill.look(at: .zero, from: [3, -2, 1], relativeTo: nil)
        anchor.addChild(fill)
        anchor.addChild(cube)
        cube.orientation = rotation
        let collider = Entity()
        collider.name = "body"
        collider.components.set(CollisionComponent(shapes: [.generateBox(size: SIMD3<Float>(repeating: 1))]))
        cube.addChild(collider)
        aura = CubeAura(parent: cube, appearance: model.configuration.appearance)
        for face in CubeFace.allCases {
            let panel = ModelEntity(mesh: .generatePlane(width: 0.84, height: 0.84, cornerRadius: 0.012))
            panel.name = face.rawValue
            panel.orientation = face.orientation
            panel.position = face.normal * 0.501
            panel.collision = CollisionComponent(shapes: [.generateBox(width: 0.84, height: 0.84, depth: 0.004)])
            panels[face] = panel
            cube.addChild(panel)
        }
        refreshTextures()
        registerForDraggedTypes([.fileURL])
        setAccessibilityLabel("T-Cube 透明立方体")
        setAccessibilityHelp("悬停显示入口；双指左右或上下旋转；右键拖动位置；右键单击设置。")
    }

    @available(*, unavailable)
    required init(frame frameRect: NSRect) { fatalError("Use init(model:)") }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(model:)") }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func refreshTextures() {
        aura.update(appearance: model.configuration.appearance)
        for (ordinal, face) in CubeFace.allCases.enumerated() {
            guard let image = CubeTheme.faceImage(group: model.configuration.group(for: face), ordinal: ordinal, appearance: model.configuration.appearance) else { continue }
            do {
                let texture = try TextureResource(image: image, options: .init(semantic: .color))
                var material = UnlitMaterial(applyPostProcessToneMap: false)
                material.color = .init(tint: .white, texture: .init(texture))
                material.blending = .transparent(opacity: .init(floatLiteral: 1))
                material.faceCulling = .back
                material.writesDepth = false
                panels[face]?.model?.materials = [material]
                panels[face]?.components.set(OpacityComponent(opacity: isHovered ? 1 : 0))
            } catch { model.report(error) }
        }
    }

    func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        for panel in panels.values { panel.components.set(OpacityComponent(opacity: hovered ? 1 : 0)) }
    }

    func containsCube(atWindowPoint point: NSPoint) -> Bool {
        if leftTracker.origin != nil || rightTracker.origin != nil { return true }
        let local = convert(point, from: nil)
        return bounds.contains(local) && !hitTest(local, query: .nearest).isEmpty
    }

    private func pointer(_ event: NSEvent) -> SIMD2<Float> {
        let point = window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        return [Float(point.x), Float(point.y)]
    }

    override func mouseDown(with event: NSEvent) {
        guard !isSnapping, !isScrolling, rightTracker.origin == nil else { return }
        leftTracker.start(at: pointer(event))
    }
    override func mouseDragged(with event: NSEvent) { leftTracker.update(to: pointer(event)) }
    override func mouseUp(with event: NSEvent) {
        guard leftTracker.end(at: pointer(event)) == .click, !isSnapping, !isScrolling else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = hitTest(point, query: .nearest).first,
              let face = CubeFace(rawValue: hit.entity.name), face == CubeRotation.nearestFace(to: rotation),
              let panel = panels[face] else { return }
        let local = panel.convert(position: hit.position, from: nil)
        guard let slot = FaceLayout.slot(at: SIMD2<Float>(local.x / 0.84, local.y / 0.84)) else { return }
        model.launch(slot: slot, face: face)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard leftTracker.origin == nil else { return }
        rightTracker.start(at: pointer(event))
        panelOrigin = window?.frame.origin ?? .zero
    }
    override func rightMouseDragged(with event: NSEvent) {
        guard rightTracker.update(to: pointer(event)) else { return }
        window?.setFrameOrigin(NSPoint(x: panelOrigin.x + CGFloat(rightTracker.translation.x), y: panelOrigin.y + CGFloat(rightTracker.translation.y)))
        NSCursor.closedHand.set()
    }
    override func rightMouseUp(with event: NSEvent) {
        let outcome = rightTracker.end(at: pointer(event))
        switch outcome {
        case .drag:
            guard let window else { return }
            let origin = NSPoint(x: panelOrigin.x + CGFloat(rightTracker.translation.x), y: panelOrigin.y + CGFloat(rightTracker.translation.y))
            let clamped = WindowPlacement.clamp(origin, size: window.frame.size, screens: NSScreen.screens.map(\.visibleFrame))
            window.setFrameOrigin(clamped)
            model.savePosition(clamped)
            NSCursor.arrow.set()
        case .click: editRequested?()
        case .none: break
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard leftTracker.origin == nil, rightTracker.origin == nil, event.momentumPhase.isEmpty else { return }
        var delta = SIMD2<Float>(Float(event.scrollingDeltaX), Float(event.scrollingDeltaY))
        if !event.hasPreciseScrollingDeltas, event.modifierFlags.contains(.shift) { delta = [delta.y, 0] }
        if delta != .zero {
            snapTask?.cancel()
            isSnapping = false
            isScrolling = true
            rotation = CubeScrollMotion.rotated(from: cube.orientation, delta: delta, precise: event.hasPreciseScrollingDeltas, inverted: event.isDirectionInvertedFromDevice)
            cube.orientation = rotation
        }
        scrollEndTask?.cancel()
        let ended = event.phase.contains(.ended) || event.phase.contains(.cancelled)
        let delay = ended ? 40 : (event.phase.isEmpty ? 180 : 320)
        scrollEndTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(delay)) }
            catch { return }
            guard let self, self.isScrolling else { return }
            self.isScrolling = false
            self.showFace(CubeScrollMotion.targetFace(for: self.cube.orientation))
        }
    }

    private func showFace(_ face: CubeFace) {
        snapTask?.cancel()
        model.selectedFace = face
        let start = cube.orientation
        let end = CubeRotation.snapped(to: face)
        isSnapping = true
        snapTask = Task { @MainActor [weak self] in
            for step in 1...14 {
                guard let self, !Task.isCancelled else { return }
                let t = Float(step) / 14
                self.cube.orientation = simd_slerp(start, end, t * t * (3 - 2 * t))
                do { try await Task.sleep(for: .milliseconds(14)) }
                catch { return }
            }
            guard let self, !Task.isCancelled else { return }
            self.rotation = end
            self.cube.orientation = end
            self.isSnapping = false
        }
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard !isSnapping, !isScrolling, leftTracker.origin == nil, rightTracker.origin == nil else { return [] }
        return sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { !isSnapping && !isScrolling && leftTracker.origin == nil && rightTracker.origin == nil }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        let face = CubeRotation.nearestFace(to: rotation)
        Task { @MainActor [weak self] in self?.model.add(urls, to: face) }
        return true
    }
}
