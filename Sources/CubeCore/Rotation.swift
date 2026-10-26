import simd

/// Right-handed coordinates: +X right, +Y up, +Z toward the viewer.
public enum CubeFace: String, CaseIterable, Codable, Sendable, Identifiable {
    case front, right, back, left, top, bottom
    public var id: String { rawValue }

    public var normal: SIMD3<Float> {
        switch self {
        case .front: [0, 0, 1]
        case .right: [1, 0, 0]
        case .back: [0, 0, -1]
        case .left: [-1, 0, 0]
        case .top: [0, 1, 0]
        case .bottom: [0, -1, 0]
        }
    }

    public var localUp: SIMD3<Float> {
        switch self {
        case .top: [0, 0, -1]
        case .bottom: [0, 0, 1]
        default: [0, 1, 0]
        }
    }

    /// Maps a panel's +Z outward normal and +Y readable top into cube coordinates.
    public var orientation: simd_quatf {
        switch self {
        case .front: simd_quatf(real: 1, imag: .zero)
        case .right: simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        case .back: simd_quatf(angle: .pi, axis: [0, 1, 0])
        case .left: simd_quatf(angle: -.pi / 2, axis: [0, 1, 0])
        case .top: simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        case .bottom: simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        }
    }
}

public enum CubeRotation {
    /// A modest three-quarter view exposes the transparent cube's depth.
    public static var displayTilt: simd_quatf {
        simd_quatf(angle: -0.66, axis: [0, 1, 0]) * simd_quatf(angle: 0.52, axis: [1, 0, 0])
    }

    public static func snapped(to face: CubeFace) -> simd_quatf {
        simd_normalize(displayTilt * face.orientation.inverse)
    }

    /// Chooses the outward normal closest to the +Z viewing direction, stable on ties.
    public static func nearestFace(to rotation: simd_quatf) -> CubeFace {
        let normalized = simd_normalize(rotation)
        var result = CubeFace.front
        var best = -Float.infinity
        for face in CubeFace.allCases {
            let score = normalized.act(face.normal).z
            if score > best { best = score; result = face }
        }
        return result
    }

    /// Total translation from mouse-down, in screen points with +Y upward (AppKit).
    public static func dragged(from initial: simd_quatf, translation: SIMD2<Float>, radiansPerPoint: Float = 0.01) -> simd_quatf {
        guard translation.x.isFinite, translation.y.isFinite, radiansPerPoint.isFinite else { return initial }
        let yaw = simd_quatf(angle: translation.x * radiansPerPoint, axis: [0, 1, 0])
        let pitch = simd_quatf(angle: -translation.y * radiansPerPoint, axis: [1, 0, 0])
        return simd_normalize(yaw * pitch * initial)
    }
}

public struct PointerDragTracker: Sendable {
    public enum Outcome: Sendable { case none, click, drag }
    public let threshold: Float
    public private(set) var origin: SIMD2<Float>?
    public private(set) var isDragging = false
    public private(set) var translation: SIMD2<Float> = .zero

    public init(threshold: Float = 5) { self.threshold = max(0, threshold) }
    public mutating func start(at point: SIMD2<Float>) {
        origin = point
        isDragging = false
        translation = .zero
    }

    @discardableResult public mutating func update(to point: SIMD2<Float>) -> Bool {
        guard let origin else { return false }
        translation = point - origin
        if simd_length(translation) >= threshold { isDragging = true }
        return isDragging
    }

    @discardableResult public mutating func end(at point: SIMD2<Float>) -> Outcome {
        guard origin != nil else { return .none }
        update(to: point)
        let outcome: Outcome = isDragging ? .drag : .click
        origin = nil
        return outcome
    }
}
