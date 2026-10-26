import test from 'node:test';
import assert from 'node:assert/strict';
import { Quaternion, Ray, Vector3 } from 'three';
import { createBodyGeometry, createFaceGeometry, faceQuaternion, iconSlotAtUV, pickCube } from '../src/core/geometry';
import { FACES } from '../src/shared/contracts';

test('quartic shell is closed with outward triangles and no duplicated seam vertices', () => {
    const g = createBodyGeometry(), p = g.getAttribute('position'), n = g.getAttribute('normal'), ids = g.index!;
    const edges = new Map<string, number>();
    const v = (i: number) => new Vector3().fromBufferAttribute(p, i);
    for (let i = 0; i < p.count; i++) {
        const a = v(i);
        assert.ok(Math.abs((a.x / 0.5) ** 4 + (a.y / 0.5) ** 4 + (a.z / 0.5) ** 4 - 1) < 1e-5);
        assert.ok(Math.abs(new Vector3().fromBufferAttribute(n, i).length() - 1) < 1e-5);
    }
    for (let i = 0; i < ids.count; i += 3) {
        const indices = [ids.getX(i), ids.getX(i + 1), ids.getX(i + 2)];
        const [a, b, c] = indices.map(v);
        assert.ok(b.clone().sub(a).cross(c.clone().sub(a)).dot(a) > 0);
        for (let j = 0; j < 3; j++) {
            const key = [indices[j], indices[(j + 1) % 3]].sort((a, b) => a - b).join(':');
            edges.set(key, (edges.get(key) ?? 0) + 1);
        }
    }
    assert.ok([...edges.values()].every(uses => uses === 2));
    assert.equal(p.count - edges.size + ids.count / 3, 2);
});

test('direct picking follows all six rendered curved decals and exact icon gaps', () => {
    for (const face of FACES) {
        const q = faceQuaternion(face);
        const normal = new Vector3(0, 0, 1).applyQuaternion(q);
        const target = new Vector3(-0.18785156, 0.14273438, 0.501).applyQuaternion(q);
        assert.deepEqual(pickCube(new Ray(target.clone().addScaledVector(normal, 3), normal.negate()), new Quaternion(), true), { face, slot: 0 });
        assert.ok(createFaceGeometry(face).getAttribute('position').count > 100);
    }
    for (const [x, y, slot] of [[-0.18785156, 0.14273438, 0], [0.18785156, 0.14273438, 1], [-0.18785156, -0.16078125, 2], [0.18785156, -0.16078125, 3]]) {
        assert.deepEqual(pickCube(new Ray(new Vector3(x, y, 3), new Vector3(0, 0, -1)), new Quaternion(), true), { face: 'front', slot });
    }
    assert.equal(iconSlotAtUV(0.5, 0.5), null);
    assert.equal(iconSlotAtUV(283 / 1024, 1 - 338 / 1024), 0);
    for (const x of [0, -0.31, 1]) assert.equal(pickCube(new Ray(new Vector3(x, 0, 3), new Vector3(0, 0, -1)), new Quaternion(), true), null);
});

test('oblique rays hit the nearest curved surface, including old-plane disagreement', () => {
    const origin = new Vector3(12, 2, 3), target = new Vector3(-0.10080372, 0.14247441, 0.50046665);
    assert.deepEqual(pickCube(new Ray(origin, target.sub(origin).normalize()), new Quaternion(), true), { face: 'front', slot: 0 });
    assert.deepEqual(pickCube(new Ray(new Vector3(3, 0, 2), new Vector3(-3, 0, -2).normalize()), new Quaternion(), false), { face: 'right', slot: null });
    assert.equal(pickCube(new Ray(new Vector3(0.48, 0.48, 3), new Vector3(0, 0, -1)), new Quaternion(), false), null);
    assert.equal(pickCube(new Ray(new Vector3(NaN, 0, 3), new Vector3(0, 0, -1)), new Quaternion(), false), null);
});

test('picking follows the presented quaternion and never selects through the nearest decal gap', () => {
    const q = new Quaternion().setFromAxisAngle(new Vector3(0, 1, 0), Math.PI / 2);
    const origin = new Vector3(-0.18785156, 0.14273438, 3).applyQuaternion(q);
    const direction = new Vector3(0, 0, -1).applyQuaternion(q);
    assert.deepEqual(pickCube(new Ray(origin, direction), q, true), { face: 'front', slot: 0 });
    assert.equal(pickCube(new Ray(new Vector3(0, 0, 3), new Vector3(0, 0, -1)), new Quaternion(), true), null);
    assert.equal(pickCube(new Ray(new Vector3(0, 0, 3), new Vector3(0, 0, 0)), new Quaternion(), false), null);
});
