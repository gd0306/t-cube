import { Box3, BufferGeometry, Float32BufferAttribute, Quaternion, Ray, Triangle, Vector2, Vector3 } from 'three';
import { FACES, type Face, type Hit } from '../shared/contracts';

export const DISPLAY_TILT = new Quaternion().setFromAxisAngle(new Vector3(0, 1, 0), -0.66)
    .multiply(new Quaternion().setFromAxisAngle(new Vector3(1, 0, 0), 0.52));
export const PANEL_SIDE = 0.84;
export const TEXTURE_SIZE = 1024;
export const ICON_RECTS = [
    { x: 175, y: 230, width: 216, height: 216 }, { x: 633, y: 230, width: 216, height: 216 },
    { x: 175, y: 600, width: 216, height: 216 }, { x: 633, y: 600, width: 216, height: 216 },
] as const;

export function faceQuaternion(face: Face): Quaternion {
    switch (face) {
        case 'front': return new Quaternion();
        case 'right': return new Quaternion().setFromAxisAngle(new Vector3(0, 1, 0), Math.PI / 2);
        case 'back': return new Quaternion().setFromAxisAngle(new Vector3(0, 1, 0), Math.PI);
        case 'left': return new Quaternion().setFromAxisAngle(new Vector3(0, 1, 0), -Math.PI / 2);
        case 'top': return new Quaternion().setFromAxisAngle(new Vector3(1, 0, 0), -Math.PI / 2);
        case 'bottom': return new Quaternion().setFromAxisAngle(new Vector3(1, 0, 0), Math.PI / 2);
    }
}
function project(direction: Vector3): Vector3 {
    return direction.clone().multiplyScalar(0.5 / (direction.x ** 4 + direction.y ** 4 + direction.z ** 4) ** 0.25);
}
function normal(point: Vector3): Vector3 { return new Vector3(point.x ** 3, point.y ** 3, point.z ** 3).normalize(); }
function geometry(positions: number[], normals: number[], uv: number[], indices: number[]): BufferGeometry {
    const result = new BufferGeometry();
    result.setAttribute('position', new Float32BufferAttribute(positions, 3));
    result.setAttribute('normal', new Float32BufferAttribute(normals, 3));
    result.setAttribute('uv', new Float32BufferAttribute(uv, 2));
    result.setIndex(indices); result.computeBoundingSphere(); return result;
}
/** A single indexed quartic shell: no independent face boundaries or UV seam vertices. */
export function createBodyGeometry(): BufferGeometry {
    const segments = 48, columns = segments * 2;
    const points: Vector3[] = [], normals: Vector3[] = [], uv: number[] = [], indices: number[] = [];
    const vertex = (direction: Vector3) => {
        const p = project(direction), point = p.clone().multiplyScalar(2);
        points.push(p); normals.push(normal(point));
        uv.push((point.x + 0.35 * point.z) / 2.7 + 0.5, (point.y + 0.25 * point.z) / 2.5 + 0.5);
    };
    vertex(new Vector3(0, 1, 0));
    for (let row = 1; row < segments; row++) {
        const theta = row * Math.PI / segments;
        for (let column = 0; column < columns; column++) {
            const phi = column * 2 * Math.PI / columns;
            vertex(new Vector3(Math.sin(theta) * Math.cos(phi), Math.cos(theta), Math.sin(theta) * Math.sin(phi)));
        }
    }
    vertex(new Vector3(0, -1, 0));
    const triangle = (a: number, b: number, c: number) => {
        const outward = normals[a].clone().add(normals[b]).add(normals[c]);
        const cross = points[b].clone().sub(points[a]).cross(points[c].clone().sub(points[a]));
        indices.push(...(cross.dot(outward) > 0 ? [a, b, c] : [a, c, b]));
    };
    for (let column = 0; column < columns; column++) {
        const next = (column + 1) % columns;
        triangle(0, 1 + column, 1 + next);
        for (let row = 0; row < segments - 2; row++) {
            const a = 1 + row * columns + column, b = 1 + row * columns + next;
            const c = 1 + (row + 1) * columns + column, d = 1 + (row + 1) * columns + next;
            triangle(a, b, d); triangle(a, d, c);
        }
        const last = 1 + (segments - 2) * columns;
        triangle(points.length - 1, last + next, last + column);
    }
    return geometry(points.flatMap(p => p.toArray()), normals.flatMap(n => n.toArray()), uv, indices);
}

/** Geometry already includes the group's orientation in cube coordinates. */
export function createFaceGeometry(face: Face): BufferGeometry {
    const segments = 32, positions: number[] = [], normals: number[] = [], uv: number[] = [], indices: number[] = [];
    const orientation = faceQuaternion(face);
    for (let row = 0; row <= segments; row++) {
        for (let column = 0; column <= segments; column++) {
            const u = column / segments, v = row / segments;
            const point = project(new Vector3((u - 0.5) * PANEL_SIDE, (v - 0.5) * PANEL_SIDE, 0.5));
            const n = normal(point);
            point.addScaledVector(n, 0.0015).applyQuaternion(orientation);
            n.applyQuaternion(orientation);
            positions.push(...point.toArray()); normals.push(...n.toArray()); uv.push(u, v);
        }
    }
    for (let row = 0; row < segments; row++) {
        for (let column = 0; column < segments; column++) {
            const a = row * (segments + 1) + column, b = a + 1, c = a + segments + 1, d = c + 1;
            indices.push(a, b, d, a, d, c);
        }
    }
    return geometry(positions, normals, uv, indices);
}

/** UV has Three's bottom-left origin, while native painted rectangles start at top-left. */
export function iconSlotAtUV(u: number, v: number): number | null {
    if (!Number.isFinite(u) || !Number.isFinite(v)) return null;
    const x = u * TEXTURE_SIZE, y = (1 - v) * TEXTURE_SIZE;
    const index = ICON_RECTS.findIndex(rect => x >= rect.x && x < rect.x + rect.width && y >= rect.y && y < rect.y + rect.height);
    return index < 0 ? null : index;
}

const bounds = new Box3(new Vector3(-0.502, -0.502, -0.502), new Vector3(0.502, 0.502, 0.502));
let body: BufferGeometry | undefined;
let faces: Map<Face, BufferGeometry> | undefined;
function intersect(ray: Ray, mesh: BufferGeometry, cull: boolean): { distance: number; uv: Vector2; point: Vector3 } | null {
    const p = mesh.getAttribute('position'), uv = mesh.getAttribute('uv'), indices = mesh.index!;
    const a = new Vector3(), b = new Vector3(), c = new Vector3(), hit = new Vector3(), bary = new Vector3();
    let nearest: { distance: number; uv: Vector2; point: Vector3 } | null = null;
    for (let i = 0; i < indices.count; i += 3) {
        const ai = indices.getX(i), bi = indices.getX(i + 1), ci = indices.getX(i + 2);
        a.fromBufferAttribute(p, ai); b.fromBufferAttribute(p, bi); c.fromBufferAttribute(p, ci);
        if (!ray.intersectTriangle(a, b, c, cull, hit)) continue;
        const distance = hit.distanceToSquared(ray.origin);
        if (nearest && distance >= nearest.distance) continue;
        Triangle.getBarycoord(hit, a, b, c, bary);
        nearest = { distance, point: hit.clone(), uv: new Vector2(
            uv.getX(ai) * bary.x + uv.getX(bi) * bary.y + uv.getX(ci) * bary.z,
            uv.getY(ai) * bary.x + uv.getY(bi) * bary.y + uv.getY(ci) * bary.z) };
    }
    return nearest;
}

export function pickCube(ray: Ray, quaternion: Quaternion, direct: boolean): Hit | null {
    if (![...ray.origin.toArray(), ...ray.direction.toArray(), ...quaternion.toArray()].every(Number.isFinite)
        || ray.direction.lengthSq() === 0 || quaternion.lengthSq() === 0) return null;
    const inverse = quaternion.clone().normalize().invert();
    const local = new Ray(ray.origin.clone().applyQuaternion(inverse), ray.direction.clone().applyQuaternion(inverse).normalize());
    if (!local.intersectsBox(bounds)) return null;
    if (direct) {
        faces ??= new Map(FACES.map(face => [face, createFaceGeometry(face)]));
        let nearest: { face: Face; distance: number; uv: Vector2 } | null = null;
        for (const [face, geometry] of faces) {
            const hit = intersect(local, geometry, true);
            if (hit && (!nearest || hit.distance < nearest.distance)) nearest = { face, ...hit };
        }
        if (!nearest) return null;
        const slot = iconSlotAtUV(nearest.uv.x, nearest.uv.y);
        return slot === null ? null : { face: nearest.face, slot };
    }
    body ??= createBodyGeometry();
    const hit = intersect(local, body, false);
    if (!hit) return null;
    const p = hit.point, x = Math.abs(p.x), y = Math.abs(p.y), z = Math.abs(p.z);
    const face: Face = x >= y && x >= z ? (p.x >= 0 ? 'right' : 'left') : y >= z ? (p.y >= 0 ? 'top' : 'bottom') : (p.z >= 0 ? 'front' : 'back');
    return { face, slot: null };
}

/** Contact point on the undeformed shell, in cube coordinates, just like native picking. */
export function pickSurfacePoint(ray: Ray, quaternion: Quaternion): Vector3 | null {
    if (![...ray.origin.toArray(), ...ray.direction.toArray(), ...quaternion.toArray()].every(Number.isFinite)
        || ray.direction.lengthSq() === 0 || quaternion.lengthSq() === 0) return null;
    const inverse = quaternion.clone().normalize().invert();
    const local = new Ray(ray.origin.clone().applyQuaternion(inverse), ray.direction.clone().applyQuaternion(inverse).normalize());
    if (!local.intersectsBox(bounds)) return null;
    body ??= createBodyGeometry();
    return intersect(local, body, false)?.point ?? null;
}
