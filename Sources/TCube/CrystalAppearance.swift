import AppKit
import RealityKit
import CubeCore
import simd

/// A transparent cube's perimeter only. Launcher content and input belong to CubeView.
/// Each ring faces outward so edges on the back cannot draw through the front.
@MainActor
final class CubeAura {
    private struct Band {
        let inner: Float
        let outer: Float
        let opacity: Float
        let isLocator: Bool
    }

    private let root = Entity()
    private var rings: [(entity: ModelEntity, band: Band)] = []
    private var appearance: CubeAppearance?
    private var gradient: TextureResource?

    init(parent: Entity, appearance: CubeAppearance) {
        root.name = "cube-aura"
        parent.addChild(root)
        // Nothing spans the interior of a face. Nested, translucent perimeter
        // bands approximate soft bloom without a renderer-wide postprocess.
        let bands = [
            Band(inner: 0.480, outer: 0.528, opacity: 0.045, isLocator: false),
            Band(inner: 0.490, outer: 0.518, opacity: 0.090, isLocator: false),
            Band(inner: 0.496, outer: 0.509, opacity: 0.160, isLocator: false),
            Band(inner: 0.498, outer: 0.502, opacity: 0.740, isLocator: false),
            Band(inner: 0.4993, outer: 0.5007, opacity: 0.160, isLocator: true)
        ]
        for band in bands {
            guard let mesh = Self.ringMesh(inner: band.inner, outer: band.outer) else { continue }
            for axis in 0..<3 {
                for sign: Float in [-1, 1] {
                    var normal = SIMD3<Float>.zero
                    normal[axis] = sign
                    let ring = ModelEntity(mesh: mesh, materials: [Self.material(opacity: 0)])
                    ring.name = band.isLocator ? "aura-locator" : "aura-gradient-rim"
                    ring.position = normal * 0.5005
                    ring.orientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: normal)
                    root.addChild(ring)
                    rings.append((ring, band))
                }
            }
        }
        update(appearance: appearance)
    }

    func update(appearance: CubeAppearance) {
        if let previous = self.appearance,
           previous.primaryHex == appearance.primaryHex,
           previous.secondaryHex == appearance.secondaryHex,
           previous.glowIntensity == appearance.glowIntensity { return }
        if self.appearance?.primaryHex != appearance.primaryHex || self.appearance?.secondaryHex != appearance.secondaryHex {
            gradient = Self.gradientTexture(appearance: appearance)
        }
        self.appearance = appearance
        let intensity = Float(max(0, min(1, appearance.glowIntensity)))
        for (entity, band) in rings {
            if band.isLocator {
                // A very faint neutral hairline remains findable on a white desktop
                // even when the optional colored aura is switched off.
                entity.model?.materials = [Self.material(opacity: band.opacity, color: NSColor(white: 0.34, alpha: 1))]
            } else {
                entity.isEnabled = intensity > 0
                entity.model?.materials = [Self.material(opacity: band.opacity * intensity, texture: gradient)]
            }
        }
    }

    private static func material(opacity: Float, color: NSColor = .white, texture: TextureResource? = nil) -> UnlitMaterial {
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        if let texture {
            material.color = .init(tint: color, texture: .init(texture))
        } else {
            material.color = .init(tint: color)
        }
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        material.faceCulling = .back
        material.writesDepth = false
        return material
    }

    private static func gradientTexture(appearance: CubeAppearance) -> TextureResource? {
        let primary = NSColor(hexRGB: appearance.primaryHex) ?? NSColor(red: 0.396, green: 0.871, blue: 1, alpha: 1)
        let secondary = NSColor(hexRGB: appearance.secondaryHex) ?? NSColor(red: 0.718, green: 0.576, blue: 1, alpha: 1)
        let size = NSSize(width: 128, height: 128)
        let image = NSImage(size: size, flipped: false) { _ in
            NSGradient(starting: primary, ending: secondary)?.draw(in: NSRect(origin: .zero, size: size), angle: 42)
            return true
        }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return try? TextureResource(image: cgImage, options: .init(semantic: .color))
    }

    private static func ringMesh(inner: Float, outer: Float) -> MeshResource? {
        let outerCorners: [SIMD3<Float>] = [[-outer, -outer, 0], [outer, -outer, 0], [outer, outer, 0], [-outer, outer, 0]]
        let innerCorners: [SIMD3<Float>] = [[-inner, -inner, 0], [inner, -inner, 0], [inner, inner, 0], [-inner, inner, 0]]
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for edge in 0..<4 {
            let next = (edge + 1) % 4
            let base = UInt32(positions.count)
            positions += [outerCorners[edge], outerCorners[next], innerCorners[next], innerCorners[edge]]
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        var mesh = MeshDescriptor(name: "transparent-perimeter-band")
        mesh.positions = .init(positions)
        mesh.normals = .init(Array(repeating: SIMD3<Float>(0, 0, 1), count: positions.count))
        mesh.textureCoordinates = .init(positions.map { SIMD2<Float>(($0.x + 0.53) / 1.06, ($0.y + 0.53) / 1.06) })
        mesh.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [mesh])
    }
}
