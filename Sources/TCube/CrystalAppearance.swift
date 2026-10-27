import AppKit
import Metal
import RealityKit
import CubeCore
import simd

/// The original glass shell, with opt-in gel rendering for the slime theme.
/// Launcher icons remain independent of both optical surfaces.
@MainActor
final class CubeAura {
    private let root = Entity()
    private var slimeMesh: SlimeShellMesh?
    private var shell: ModelEntity?
    private var gel: ModelEntity?
    private var pearl: ModelEntity?
    private var chroma: ModelEntity?
    private var energy: ModelEntity?
    private var pearlMaterial: UnlitMaterial?
    private var chromaMaterial: UnlitMaterial?
    private var energyMaterial: UnlitMaterial?
    private var appearance: CubeAppearance?
    private var motion = PrismMotion()
    private static let mesh = bodyMesh()
    private static let pearlTexture = opticalTexture(layer: .pearl)
    private static let slimePearlTexture = opticalTexture(layer: .slimePearl)

    init(parent: Entity, appearance: CubeAppearance) {
        root.name = "cube-aura"
        // Fade only optical layers; launcher decals are siblings and stay crisp.
        root.components.set(OpacityComponent(opacity: 0.25))
        parent.addChild(root)
        if let mesh = Self.mesh {
            let shell = ModelEntity(mesh: mesh, materials: [Self.shellMaterial(slime: false)])
            shell.name = "glass-shell"
            root.addChild(shell)
            self.shell = shell
            let gel = ModelEntity(mesh: mesh, materials: [Self.material(texture: nil)])
            gel.name = "slime-gel"
            gel.isEnabled = false
            root.addChild(gel)
            self.gel = gel
            let pearlMaterial = Self.material(texture: Self.pearlTexture)
            let pearl = ModelEntity(mesh: mesh, materials: [pearlMaterial])
            pearl.name = "glass-pearl"
            root.addChild(pearl)
            self.pearl = pearl
            self.pearlMaterial = pearlMaterial
            let chroma = ModelEntity(mesh: mesh, materials: [Self.material(texture: nil)])
            chroma.name = "glass-flow"
            root.addChild(chroma)
            self.chroma = chroma
        }
        let energy = ModelEntity(mesh: .generateSphere(radius: 0.26), materials: [Self.material(texture: nil)])
        energy.name = "glass-inner-light"
        root.addChild(energy)
        self.energy = energy
        update(appearance: appearance)
    }

    func update(appearance: CubeAppearance) {
        guard appearance != self.appearance else { return }
        let isSlime = appearance.surfaceStyle == .slime
        if appearance.surfaceStyle != self.appearance?.surfaceStyle {
            if isSlime {
                if slimeMesh == nil { slimeMesh = try? SlimeShellMesh() }
                slimeMesh?.update(SlimeDeformation())
            }
            let activeMesh = isSlime ? (slimeMesh?.resource ?? Self.mesh) : Self.mesh
            if let activeMesh {
                for entity in [shell, gel, pearl, chroma] { entity?.model?.mesh = activeMesh }
            }
            root.components.set(OpacityComponent(opacity: isSlime ? 0.55 : 0.25))
            shell?.model?.materials = [Self.shellMaterial(slime: isSlime)]
            pearlMaterial = Self.material(texture: isSlime ? Self.slimePearlTexture : Self.pearlTexture)
            gel?.isEnabled = isSlime
        }
        if appearance.primaryHex != self.appearance?.primaryHex || appearance.secondaryHex != self.appearance?.secondaryHex || appearance.surfaceStyle != self.appearance?.surfaceStyle {
            if isSlime { gel?.model?.materials = [Self.material(texture: Self.opticalTexture(layer: .gel, appearance: appearance))] }
            chromaMaterial = Self.material(texture: Self.opticalTexture(layer: .chroma, appearance: appearance))
            energyMaterial = appearance.surfaceStyle == .clear ? nil : Self.material(texture: Self.opticalTexture(layer: .energy, appearance: appearance))
        }
        self.appearance = appearance
        applyLight()
    }

    func deform(_ deformation: SlimeDeformation) {
        guard appearance?.surfaceStyle == .slime else { return }
        slimeMesh?.update(deformation)
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
        pearl?.components.set(OpacityComponent(opacity: 0.55 + 0.20 * engagement))
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
        chroma?.components.set(OpacityComponent(opacity: intensity * (0.55 + 0.25 * engagement) * breathing))
    }

    private static func shellMaterial(slime: Bool) -> PhysicallyBasedMaterial {
        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: NSColor(white: 1, alpha: slime ? 0.10 : 0.035))
        glass.roughness = .init(floatLiteral: slime ? 0.10 : 0.20)
        glass.specular = .init(floatLiteral: 0.50)
        glass.clearcoat = .init(floatLiteral: slime ? 1 : 0.55)
        glass.clearcoatRoughness = .init(floatLiteral: slime ? 0.08 : 0.20)
        glass.blending = .transparent(opacity: .init(floatLiteral: slime ? 0.28 : 1))
        glass.faceCulling = .back
        glass.writesDepth = false
        return glass
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

    private enum OpticalLayer: Equatable { case gel, pearl, slimePearl, chroma, energy }

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
                case .gel:
                    let mix = 0.5 + 0.5 * sin(2 * .pi * (u + 0.1))
                    color = (a * (1 - mix) + b * mix) * 0.85 + SIMD3(repeating: 0.15)
                    let rim = pow(abs(2 * v - 1), 3)
                    alpha = 0.32 + 0.32 * rim + 0.12 * gaussian(v, 0.25, 0.18)
                case .pearl, .slimePearl:
                    color = SIMD3(0.94, 0.98, 1)
                    let crest = 0.70 + 0.12 * cos(2 * .pi * u)
                    let profile = layer == .slimePearl
                        ? 0.68 * gaussian(v, crest, 0.045) + 0.10 * gaussian(v, 0.72, 0.20)
                        : 0.20 * gaussian(v, crest, 0.055) + 0.035 * gaussian(v, 0.72, 0.22)
                    alpha = profile * (0.35 + 0.65 * wave * wave)
                case .chroma:
                    let mix = 0.5 + 0.5 * sin(2 * .pi * (u + 0.12))
                    let blend = a * (1 - mix) + b * mix
                    switch appearance.surfaceStyle {
                    case .iridescent:
                        let warmth = 0.46 * pow(max(0, sin(2 * .pi * (u - 0.18))), 6)
                        color = blend * (1 - warmth) + SIMD3(1, 0.83, 0.67) * warmth
                        alpha = gaussian(v, 0.38 + 0.14 * sin(2 * .pi * u), 0.20) * (0.06 + 0.09 * pow(wave, 4))
                    case .moonstone:
                        color = blend * 0.35 + SIMD3(repeating: 0.65)
                        alpha = gaussian(v, 0.52, 0.28) * (0.04 + 0.08 * wave)
                    case .aurora, .slime:
                        color = blend * 0.85 + SIMD3(repeating: 0.15)
                        let fold = 0.45 + 0.15 * sin(2 * .pi * u)
                        alpha = gaussian(v, fold, 0.16) * (0.07 + 0.12 * wave * wave)
                    case .clear:
                        color = blend * 0.8 + SIMD3(repeating: 0.2)
                        alpha = gaussian(v, 0.42, 0.24) * (0.025 + 0.055 * wave * wave)
                    }
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

    private static func bodyMesh() -> MeshResource? {
        let geometry = SoftGlassGeometry()
        var mesh = MeshDescriptor(name: "soft-glass-body")
        mesh.positions = .init(geometry.positions)
        mesh.normals = .init(geometry.normals)
        mesh.textureCoordinates = .init(geometry.textureCoordinates)
        mesh.primitives = .triangles(geometry.indices)
        return try? MeshResource.generate(from: [mesh])
    }
}
