import AppKit
import Metal
import RealityKit
import CubeCore
import simd

/// Open, rounded glass edges. Optical contrast, pearl and chromatic light are
/// separate layers. Face interiors stay transparent; new materials add faint
/// inner light that recedes while the user chooses an app.
@MainActor
final class CubeAura {
    private let root = Entity()
    private var pearl: ModelEntity?
    private var chroma: ModelEntity?
    private var energy: ModelEntity?
    private var facets: [ModelEntity] = []
    private var pearlMaterial: UnlitMaterial?
    private var chromaMaterial: UnlitMaterial?
    private var energyMaterial: UnlitMaterial?
    private var facetMaterial: UnlitMaterial?
    private var appearance: CubeAppearance?
    private var motion = PrismMotion()
    private static let mesh = frameMesh()
    private static let pearlTexture = opticalTexture(layer: .pearl)
    private static let shadeTexture = opticalTexture(layer: .shade)
    private static let facetTexture = opticalTexture(layer: .facet)

    init(parent: Entity, appearance: CubeAppearance) {
        root.name = "cube-aura"
        parent.addChild(root)
        if let mesh = Self.mesh {
            let shade = ModelEntity(mesh: mesh, materials: [Self.material(texture: Self.shadeTexture)])
            shade.name = "prism-contrast"
            root.addChild(shade)
            let pearlMaterial = Self.material(texture: Self.pearlTexture)
            let pearl = ModelEntity(mesh: mesh, materials: [pearlMaterial])
            pearl.name = "prism-pearl"
            root.addChild(pearl)
            self.pearl = pearl
            self.pearlMaterial = pearlMaterial
            let chroma = ModelEntity(mesh: mesh, materials: [Self.material(texture: nil)])
            chroma.name = "prism-flow"
            root.addChild(chroma)
            self.chroma = chroma
        }
        let energy = ModelEntity(mesh: .generateSphere(radius: 0.26), materials: [Self.material(texture: nil)])
        energy.name = "glass-inner-light"
        root.addChild(energy)
        self.energy = energy
        let facetMaterial = Self.material(texture: Self.facetTexture)
        self.facetMaterial = facetMaterial
        let facetMesh = MeshResource.generatePlane(width: 0.93, height: 0.93, cornerRadius: 0.025)
        for face in CubeFace.allCases {
            let facet = ModelEntity(mesh: facetMesh, materials: [facetMaterial])
            facet.name = "prism-facet-\(face.rawValue)"
            facet.orientation = face.orientation
            facet.position = face.normal * 0.5002
            root.addChild(facet)
            facets.append(facet)
        }
        update(appearance: appearance)
    }

    func update(appearance: CubeAppearance) {
        guard appearance != self.appearance else { return }
        if appearance.primaryHex != self.appearance?.primaryHex || appearance.secondaryHex != self.appearance?.secondaryHex || appearance.surfaceStyle != self.appearance?.surfaceStyle {
            chromaMaterial = Self.material(texture: Self.opticalTexture(layer: .chroma, appearance: appearance))
            energyMaterial = appearance.surfaceStyle == .clear ? nil : Self.material(texture: Self.opticalTexture(layer: .energy, appearance: appearance))
        }
        self.appearance = appearance
        applyLight()
    }

    func advance(deltaTime: TimeInterval, hovered: Bool, reducedMotion: Bool) {
        let previousPhase = motion.phase
        let previousEngagement = motion.engagement
        motion.advance(deltaTime: deltaTime, hovered: hovered, reducedMotion: reducedMotion)
        guard motion.phase != previousPhase || motion.engagement != previousEngagement else { return }
        applyLight()
    }

    private func applyLight() {
        let engagement = Float(motion.engagement)
        let phase = Float(motion.phase)
        if var material = pearlMaterial {
            material.textureCoordinateTransform.offset = [-phase, 0]
            pearl?.model?.materials = [material]
        }
        if var material = chromaMaterial {
            material.textureCoordinateTransform.offset = [phase, 0]
            chroma?.model?.materials = [material]
        }
        if var material = facetMaterial {
            material.textureCoordinateTransform.offset = [phase, 0]
            for facet in facets {
                facet.isEnabled = engagement > 0
                if engagement > 0 {
                    facet.model?.materials = [material]
                    facet.components.set(OpacityComponent(opacity: engagement))
                }
            }
        }
        pearl?.components.set(OpacityComponent(opacity: 0.62 + 0.28 * engagement))
        let intensity = Float(max(0, min(1, appearance?.glowIntensity ?? 0)))
        energy?.isEnabled = appearance?.surfaceStyle != .clear && intensity > 0
        if energy?.isEnabled == true, var material = energyMaterial {
            material.textureCoordinateTransform.offset = [phase, 0]
            energy?.model?.materials = [material]
            // The shell is the focus; interior light recedes when choosing apps.
            let strength: Float = appearance?.surfaceStyle == .moonstone ? 0.10 : 0.20
            energy?.components.set(OpacityComponent(opacity: intensity * strength * (1 - 0.86 * engagement)))
        }
        let breathing = Float(0.94 + 0.06 * sin(motion.phase * 2 * .pi))
        chroma?.isEnabled = intensity > 0
        chroma?.components.set(OpacityComponent(opacity: intensity * (0.34 + 0.46 * engagement) * breathing))
    }

    private static func material(texture: TextureResource?) -> UnlitMaterial {
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        if let texture {
            let sampler = MTLSamplerDescriptor()
            sampler.sAddressMode = .repeat
            sampler.tAddressMode = .clampToEdge
            sampler.minFilter = .linear
            sampler.magFilter = .linear
            material.color = .init(tint: .white, texture: .init(texture, sampler: .init(sampler)))
        } else { material.color = .init(tint: .clear) }
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        material.faceCulling = .back
        material.writesDepth = false
        return material
    }

    private enum OpticalLayer { case shade, pearl, chroma, facet, energy }

    private static func opticalTexture(layer: OpticalLayer, appearance: CubeAppearance = CubeAppearance()) -> TextureResource? {
        let primary = (NSColor(hexRGB: appearance.primaryHex) ?? .cyan).usingColorSpace(.sRGB) ?? .cyan
        let secondary = (NSColor(hexRGB: appearance.secondaryHex) ?? .white).usingColorSpace(.sRGB) ?? .white
        let a = SIMD3(Double(primary.redComponent), Double(primary.greenComponent), Double(primary.blueComponent))
        let b = SIMD3(Double(secondary.redComponent), Double(secondary.greenComponent), Double(secondary.blueComponent))
        let width = 512, height = 256
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        func gaussian(_ value: Double, _ center: Double, _ width: Double) -> Double {
            exp(-pow((value - center) / width, 2))
        }
        for y in 0..<height {
            // CGImage rows start at the top; RealityKit's UV origin is bottom-left.
            let v = 1 - Double(y) / Double(height - 1)
            for x in 0..<width {
                let u = Double(x) / Double(width)
                let wave = 0.5 + 0.5 * cos(2 * .pi * u)
                let color: SIMD3<Double>
                let alpha: Double
                switch layer {
                case .shade:
                    color = SIMD3(0.035, 0.055, 0.075)
                    alpha = 0.07 * gaussian(v, 0.995, 0.025)
                case .pearl:
                    color = SIMD3(0.94, 0.98, 1)
                    let profile = 0.46 * gaussian(v, 0.96, 0.035) + 0.015 * gaussian(v, 0.81, 0.18)
                    alpha = profile * (0.50 + 0.50 * wave * wave)
                case .chroma:
                    let mix = 0.5 + 0.5 * sin(2 * .pi * (u + 0.12))
                    let blend = a * (1 - mix) + b * mix
                    switch appearance.surfaceStyle {
                    case .iridescent:
                        let warmth = 0.46 * pow(max(0, sin(2 * .pi * (u - 0.18))), 6)
                        color = blend * (1 - warmth) + SIMD3(1, 0.83, 0.67) * warmth
                        alpha = gaussian(v, 0.95, 0.07) * (0.08 + 0.26 * pow(wave, 4))
                    case .moonstone:
                        color = blend * 0.35 + SIMD3(repeating: 0.65)
                        alpha = gaussian(v, 0.95, 0.085) * (0.06 + 0.18 * wave)
                    case .aurora:
                        color = blend * 0.85 + SIMD3(repeating: 0.15)
                        let fold = 0.94 + 0.025 * sin(4 * .pi * u)
                        alpha = gaussian(v, fold, 0.075) * (0.08 + 0.28 * wave * wave)
                    case .clear:
                        color = blend * 0.8 + SIMD3(repeating: 0.2)
                        alpha = gaussian(v, 0.95, 0.07) * (0.06 + 0.26 * pow(wave, 4))
                    }
                case .facet:
                    color = SIMD3(0.93, 0.97, 1)
                    let diagonal = (u + v * 0.35).truncatingRemainder(dividingBy: 1)
                    alpha = 0.065 * gaussian(diagonal, 0.5, 0.09)
                case .energy:
                    let mix = 0.5 + 0.5 * sin(2 * .pi * u)
                    let blend = a * (1 - mix) + b * mix
                    color = blend * 0.65 + SIMD3(repeating: 0.35)
                    let first = 0.50 + 0.20 * sin(4 * .pi * u)
                    let second = 0.48 + 0.24 * cos(2 * .pi * u + 0.8)
                    let third = 0.52 + 0.18 * sin(6 * .pi * u + 1.7)
                    let threads = gaussian(v, first, 0.012) + gaussian(v, second, 0.014) + gaussian(v, third, 0.010)
                    let halo = gaussian(v, first, 0.045) + gaussian(v, second, 0.045)
                    alpha = min(1, 0.72 * threads + 0.06 * halo) * gaussian(v, 0.5, 0.32)
                }
                let index = (y * width + x) * 4
                pixels[index] = UInt8(max(0, min(255, (color.x * 255).rounded())))
                pixels[index + 1] = UInt8(max(0, min(255, (color.y * 255).rounded())))
                pixels[index + 2] = UInt8(max(0, min(255, (color.z * 255).rounded())))
                pixels[index + 3] = UInt8(max(0, min(255, (alpha * 255).rounded())))
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return try? TextureResource(image: image, options: .init(semantic: .color))
    }

    private static func frameMesh() -> MeshResource? {
        let geometry = RoundedCubeFrameGeometry(halfExtent: 0.5, cornerRadius: 0.028, segments: 32)
        var mesh = MeshDescriptor(name: "prism-rounded-frame")
        mesh.positions = .init(geometry.positions)
        mesh.normals = .init(geometry.normals)
        mesh.textureCoordinates = .init(zip(geometry.positions, geometry.normals).map { position, normal in
            let u = (position.x + 0.62 * position.y + 0.39 * position.z + 1.005) / 2.01
            return SIMD2(u, max(abs(normal.x), max(abs(normal.y), abs(normal.z))))
        })
        mesh.primitives = .triangles(geometry.indices)
        return try? MeshResource.generate(from: [mesh])
    }
}
