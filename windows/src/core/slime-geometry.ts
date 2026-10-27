import { BufferAttribute, BufferGeometry, DynamicDrawUsage, Vector3 } from 'three';
import type { SlimeDeformation } from './slime';

/** Stream only shell vertices; the rigid input remains available for stable picking. */
export class SlimeShell {
    readonly geometry: BufferGeometry;
    private readonly positions: Float32Array;
    private readonly normals: Float32Array;
    private readonly point = new Vector3();
    private readonly normal = new Vector3();
    private readonly result = new Vector3();

    constructor(base: BufferGeometry) {
        this.geometry = base.clone();
        this.positions = Float32Array.from(base.getAttribute('position').array);
        this.normals = Float32Array.from(base.getAttribute('normal').array);
        const position = this.geometry.getAttribute('position');
        const normal = this.geometry.getAttribute('normal');
        if (!(position instanceof BufferAttribute) || !(normal instanceof BufferAttribute))
            throw new Error('Slime shell requires separate position and normal buffers');
        position.setUsage(DynamicDrawUsage);
        normal.setUsage(DynamicDrawUsage);
        // All bounded spring states fit this envelope; no stale frustum culling.
        this.geometry.boundingSphere!.radius = 1.4;
    }

    update(deformation: SlimeDeformation): void {
        const positions = this.geometry.getAttribute('position');
        const normals = this.geometry.getAttribute('normal');
        for (let i = 0; i < positions.count; i++) {
            this.point.fromArray(this.positions, i * 3);
            this.normal.fromArray(this.normals, i * 3);
            deformation.position(this.point, this.result);
            positions.setXYZ(i, this.result.x, this.result.y, this.result.z);
            deformation.normal(this.normal, this.point, this.result);
            normals.setXYZ(i, this.result.x, this.result.y, this.result.z);
        }
        positions.needsUpdate = normals.needsUpdate = true;
    }

    reset(): void {
        this.geometry.getAttribute('position').array.set(this.positions);
        this.geometry.getAttribute('normal').array.set(this.normals);
        this.geometry.getAttribute('position').needsUpdate = true;
        this.geometry.getAttribute('normal').needsUpdate = true;
    }
}
