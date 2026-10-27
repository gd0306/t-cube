import RealityKit
import CubeCore
import simd

/// Reuses one mesh across all optical layers and streams only vertex buffers.
/// Topology and UVs never change, so movement does not rebuild GPU resources.
@MainActor
final class SlimeShellMesh {
    let resource: MeshResource
    private let mesh: LowLevelMesh
    private let geometry = SoftGlassGeometry(segments: 32)

    init() throws {
        let geometry = self.geometry
        let descriptor = LowLevelMesh.Descriptor(
            vertexCapacity: geometry.positions.count,
            vertexAttributes: [
                .init(semantic: .position, format: .float3, layoutIndex: 0, offset: 0),
                .init(semantic: .normal, format: .float3, layoutIndex: 1, offset: 0),
                .init(semantic: .uv0, format: .float2, layoutIndex: 2, offset: 0)
            ],
            vertexLayouts: [
                .init(bufferIndex: 0, bufferStride: MemoryLayout<SIMD3<Float>>.stride),
                .init(bufferIndex: 1, bufferStride: MemoryLayout<SIMD3<Float>>.stride),
                .init(bufferIndex: 2, bufferStride: MemoryLayout<SIMD2<Float>>.stride)
            ],
            indexCapacity: geometry.indices.count)
        mesh = try LowLevelMesh(descriptor: descriptor)
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
            geometry.positions.withUnsafeBytes { bytes.copyMemory(from: $0) }
        }
        mesh.withUnsafeMutableBytes(bufferIndex: 1) { bytes in
            geometry.normals.withUnsafeBytes { bytes.copyMemory(from: $0) }
        }
        mesh.withUnsafeMutableIndices { bytes in
            geometry.indices.withUnsafeBytes { bytes.copyMemory(from: $0) }
        }
        mesh.withUnsafeMutableBytes(bufferIndex: 2) { bytes in
            geometry.textureCoordinates.withUnsafeBytes { bytes.copyMemory(from: $0) }
        }
        mesh.parts.replaceAll([.init(indexCount: geometry.indices.count,
                                    bounds: BoundingBox(min: [-0.8, -0.8, -0.8], max: [0.8, 0.8, 0.8]))])
        resource = try MeshResource(from: mesh)
    }

    func update(_ deformation: SlimeDeformation) {
        mesh.replaceUnsafeMutableBytes(bufferIndex: 0) { bytes in
            let positions = bytes.bindMemory(to: SIMD3<Float>.self)
            for index in geometry.positions.indices {
                positions[index] = deformation.position(geometry.positions[index])
            }
        }
        mesh.replaceUnsafeMutableBytes(bufferIndex: 1) { bytes in
            let normals = bytes.bindMemory(to: SIMD3<Float>.self)
            for index in geometry.positions.indices {
                normals[index] = deformation.normal(geometry.normals[index], at: geometry.positions[index])
            }
        }
    }
}
