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
    private(set) var isHovered = false
    var editRequested: (() -> Void)?
    var faceRequested: ((CubeFace, NSRect) -> Void)?

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
        setAccessibilityHelp("悬停显示入口；滚动旋转；按住拖动位置；单击面立即展开入口；右键单击设置。")
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
        guard rightTracker.origin == nil else { return }
        leftTracker.start(at: pointer(event))
        panelOrigin = window?.frame.origin ?? .zero
    }
    override func mouseDragged(with event: NSEvent) {
        guard leftTracker.update(to: pointer(event)) else { return }
        window?.setFrameOrigin(NSPoint(x: panelOrigin.x + CGFloat(leftTracker.translation.x), y: panelOrigin.y + CGFloat(leftTracker.translation.y)))
        NSCursor.closedHand.set()
    }
    override func mouseUp(with event: NSEvent) {
        let outcome = leftTracker.end(at: pointer(event))
        if outcome == .drag {
            finishMove(translation: leftTracker.translation)
            return
        }
        guard outcome == .click else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let ray = ray(through: point),
              let face = CubeFacePicking.face(origin: cube.convert(position: ray.origin, from: nil),
                                               direction: cube.convert(direction: ray.direction, from: nil)) else { return }
        model.selectedFace = face
        faceRequested?(face, NSRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2))
    }

    private func finishMove(translation: SIMD2<Float>) {
        guard let window else { return }
        let origin = NSPoint(x: panelOrigin.x + CGFloat(translation.x), y: panelOrigin.y + CGFloat(translation.y))
        let clamped = WindowPlacement.clamp(origin, size: window.frame.size, screens: NSScreen.screens.map(\.visibleFrame))
        window.setFrameOrigin(clamped)
        model.savePosition(clamped)
        NSCursor.arrow.set()
    }

    func cancelRightDrag() {
        if rightTracker.isDragging, let window {
            let clamped = WindowPlacement.clamp(window.frame.origin, size: window.frame.size, screens: NSScreen.screens.map(\.visibleFrame))
            window.setFrameOrigin(clamped)
            model.savePosition(clamped)
        }
        rightTracker = PointerDragTracker()
        NSCursor.arrow.set()
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
            finishMove(translation: rightTracker.translation)
        case .click: editRequested?()
        case .none: break
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard leftTracker.origin == nil, rightTracker.origin == nil, event.momentumPhase.isEmpty else { return }
        var delta = SIMD2<Float>(Float(event.scrollingDeltaX), Float(event.scrollingDeltaY))
        if !event.hasPreciseScrollingDeltas, event.modifierFlags.contains(.shift) { delta = [delta.y, 0] }
        rotate(with: delta, precise: event.hasPreciseScrollingDeltas, inverted: event.isDirectionInvertedFromDevice)
    }

    func rotate(with delta: SIMD2<Float>, precise: Bool, inverted: Bool) {
        guard delta != .zero else { return }
        rotation = CubeScrollMotion.rotated(from: cube.orientation, delta: delta, precise: precise, inverted: inverted)
        cube.orientation = rotation
        model.selectedFace = CubeScrollMotion.targetFace(for: rotation)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard leftTracker.origin == nil, rightTracker.origin == nil else { return [] }
        return sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { leftTracker.origin == nil && rightTracker.origin == nil }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        let face = CubeRotation.nearestFace(to: rotation)
        Task { @MainActor [weak self] in self?.model.add(urls, to: face) }
        return true
    }
}
