import assert from 'node:assert/strict';
import { test } from 'node:test';
import { Vector3 } from 'three';
import { createBodyGeometry } from '../src/core/geometry';
import { SlimeMotion } from '../src/core/slime';
import { SlimeShell } from '../src/core/slime-geometry';

test('elastic shell moves vertices with corrected normals without changing the rigid input or UV topology', () => {
    const base = createBodyGeometry();
    const original = Array.from(base.getAttribute('position').array);
    const shell = new SlimeShell(base);
    const motion = new SlimeMotion();
    motion.setContact(new Vector3(0, 0, 0.5));
    for (let i = 0; i < 30; i++) motion.step(1 / 60, false);
    shell.update(motion.deformation);
    const positions = shell.geometry.getAttribute('position');
    const normals = shell.geometry.getAttribute('normal');
    let pulled = false;
    for (let i = 0; i < positions.count; i++) {
        pulled ||= positions.getZ(i) > 0.56;
        const normal = new Vector3().fromBufferAttribute(normals, i);
        assert.ok(Number.isFinite(normal.length()) && Math.abs(normal.length() - 1) < 0.00001);
    }
    assert.ok(pulled);
    assert.deepEqual(Array.from(base.getAttribute('position').array), original);
    assert.deepEqual(shell.geometry.index!.array, base.index!.array);
    assert.deepEqual(shell.geometry.getAttribute('uv').array, base.getAttribute('uv').array);
    shell.reset();
    assert.deepEqual(Array.from(shell.geometry.getAttribute('position').array), original);
    assert.deepEqual(shell.geometry.getAttribute('normal').array, base.getAttribute('normal').array);
    shell.geometry.dispose();
    base.dispose();
});
