import AppKit
import RealityKit
import CubeCore
import simd
import Combine

@MainActor
final class CubeView: ARView {
    let model: AppModel
    let cube = Entity()
    private let anchor = AnchorEntity(world: .zero)
    private var panels: [CubeFace: ModelEntity] = [:]
    private var aura: CubeAura!
    private var lightUpdates: (any Cancellable)?
    private var lightElapsed: TimeInterval = 0
    private var leftTracker = PointerDragTracker()
    private var leftMoveOnly = false
    private var rightTracker = PointerDragTracker()
    private var rotation = CubeRotation.snapped(to: .front)
    private var panelOrigin = NSPoint.zero
    private(set) var isHovered = false
    var editRequested: (() -> Void)?
    var faceRequested: ((CubeFace, NSRect) -> Void)?
    var launchRequested: ((Int, CubeFace) -> Void)?
    var interactionChanged: ((Bool) -> Void)?
    var positionCommitted: ((NSRect) -> Void)?

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
        aura = CubeAura(parent: cube, appearance: model.displayedAppearance)
        for face in CubeFace.allCases {
            let panel = ModelEntity(mesh: .generatePlane(width: FaceLayout.panelSide, height: FaceLayout.panelSide, cornerRadius: 0.012))
            panel.name = face.rawValue
            panel.orientation = face.orientation
            panel.position = face.normal * FaceLayout.panelDistance
            panel.collision = CollisionComponent(shapes: [.generateBox(width: 0.84, height: 0.84, depth: 0.004)])
            panels[face] = panel
            cube.addChild(panel)
        }
        refreshTextures()
        registerForDraggedTypes([.fileURL])
        setAccessibilityLabel("T-Cube 透明立方体")
        lightUpdates = scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.window?.isVisible == true else { self.lightElapsed = 0; return }
                self.lightElapsed += event.deltaTime
                guard self.lightElapsed >= 1.0 / 30 else { return }
                self.aura.advance(deltaTime: self.lightElapsed, hovered: self.isHovered, reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
                self.lightElapsed = 0
            }
        }
    }

    @available(*, unavailable)
    required init(frame frameRect: NSRect) { fatalError("Use init(model:)") }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(model:)") }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func refreshTextures() {
        refreshAppearance()
        setAccessibilityHelp(model.configuration.expandsFacesOnClick
            ? "悬停显示入口；滚动旋转；按住拖动位置；单击面展开入口；右键单击设置。"
            : "悬停显示入口；滚动旋转；按住拖动位置；单击图标直接打开；右键单击设置。")
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

    func refreshAppearance() { aura.update(appearance: model.displayedAppearance) }

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
        let point = window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        beginPrimaryDrag(atScreenPoint: point)
    }

    func beginPrimaryDrag(atScreenPoint point: NSPoint, moveOnly: Bool = false) {
        guard rightTracker.origin == nil else { return }
        leftMoveOnly = moveOnly
        leftTracker.start(at: [Float(point.x), Float(point.y)])
        panelOrigin = window?.frame.origin ?? .zero
        interactionChanged?(true)
    }
    override func mouseDragged(with event: NSEvent) {
        guard leftTracker.update(to: pointer(event)) else { return }
        window?.setFrameOrigin(NSPoint(x: panelOrigin.x + CGFloat(leftTracker.translation.x), y: panelOrigin.y + CGFloat(leftTracker.translation.y)))
        NSCursor.closedHand.set()
    }
    override func mouseUp(with event: NSEvent) {
        guard leftTracker.origin != nil else { return }
        defer { leftMoveOnly = false; interactionChanged?(false) }
        let outcome = leftTracker.end(at: pointer(event))
        if outcome == .drag {
            finishMove(translation: leftTracker.translation)
            return
        }
        guard outcome == .click, !leftMoveOnly else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let ray = ray(through: point) else { return }
        let origin = cube.convert(position: ray.origin, from: nil)
        let direction = cube.convert(direction: ray.direction, from: nil)
        if model.configuration.expandsFacesOnClick {
            guard let face = CubeFacePicking.face(origin: origin, direction: direction) else { return }
            model.selectedFace = face
            faceRequested?(face, NSRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2))
        } else {
            guard isHovered, let hit = CubeFacePicking.icon(origin: origin, direction: direction),
                  model.configuration.group(for: hit.face).slots[hit.slot] != nil else { return }
            model.selectedFace = hit.face
            launchRequested?(hit.slot, hit.face)
        }
    }

    private func finishMove(translation: SIMD2<Float>) {
        guard let window else { return }
        let origin = NSPoint(x: panelOrigin.x + CGFloat(translation.x), y: panelOrigin.y + CGFloat(translation.y))
        let clamped = WindowPlacement.clamp(origin, size: window.frame.size, screens: NSScreen.screens.map(\.visibleFrame))
        window.setFrameOrigin(clamped)
        if let positionCommitted { positionCommitted(window.frame) }
        else { model.savePosition(clamped) }
        NSCursor.arrow.set()
    }

    func cancelRightDrag() {
        guard rightTracker.origin != nil else { return }
        defer { interactionChanged?(false) }
        if rightTracker.isDragging, let window {
            let clamped = WindowPlacement.clamp(window.frame.origin, size: window.frame.size, screens: NSScreen.screens.map(\.visibleFrame))
            window.setFrameOrigin(clamped)
            if let positionCommitted { positionCommitted(window.frame) }
            else { model.savePosition(clamped) }
        }
        rightTracker = PointerDragTracker()
        NSCursor.arrow.set()
    }

    func cancelPrimaryDrag() {
        guard leftTracker.origin != nil else { return }
        if leftTracker.isDragging { finishMove(translation: leftTracker.translation) }
        leftTracker = PointerDragTracker()
        leftMoveOnly = false
        NSCursor.arrow.set()
        interactionChanged?(false)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        beginSecondaryDrag(atScreenPoint: point)
    }

    func beginSecondaryDrag(atScreenPoint point: NSPoint) {
        guard leftTracker.origin == nil else { return }
        rightTracker.start(at: [Float(point.x), Float(point.y)])
        panelOrigin = window?.frame.origin ?? .zero
        interactionChanged?(true)
    }
    override func rightMouseDragged(with event: NSEvent) {
        guard rightTracker.update(to: pointer(event)) else { return }
        window?.setFrameOrigin(NSPoint(x: panelOrigin.x + CGFloat(rightTracker.translation.x), y: panelOrigin.y + CGFloat(rightTracker.translation.y)))
        NSCursor.closedHand.set()
    }
    override func rightMouseUp(with event: NSEvent) {
        guard rightTracker.origin != nil else { return }
        defer { interactionChanged?(false) }
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
