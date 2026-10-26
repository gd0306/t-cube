import test from 'node:test';
import assert from 'node:assert/strict';
import { Vector3 } from 'three';
import { DISPLAY_TILT } from '../src/core/geometry';
import { applyScrollRotation, IdleRotation, PrismMotion } from '../src/core/rotation';

test('scroll turns continuously in tilt-relative axes with bounded precise deltas', () => {
    const horizontal = applyScrollRotation(DISPLAY_TILT, 1, 0, false);
    const vertical = applyScrollRotation(DISPLAY_TILT, 0, 1, false);
    const inverse = DISPLAY_TILT.clone().invert();
    assert.ok(new Vector3(0, 0, 1).applyQuaternion(inverse.clone().multiply(horizontal)).distanceTo(new Vector3(-1, 0, 0)) < 1e-6);
    assert.ok(new Vector3(0, 0, 1).applyQuaternion(inverse.clone().multiply(vertical)).distanceTo(new Vector3(0, 1, 0)) < 1e-6);
    const small = applyScrollRotation(DISPLAY_TILT, 0.1, 0, true);
    assert.ok(small.angleTo(DISPLAY_TILT) > 0 && small.angleTo(DISPLAY_TILT) < 0.01);
    assert.ok(applyScrollRotation(DISPLAY_TILT, 10000, -10000, true).angleTo(applyScrollRotation(DISPLAY_TILT, 100, -100, true)) < 1e-6);
    assert.ok(applyScrollRotation(DISPLAY_TILT, NaN, 1, true).angleTo(DISPLAY_TILT) < 1e-6);
});

test('seeded idle motion pauses without accumulating time and remains normalized', () => {
    const a = new IdleRotation(23), b = new IdleRotation(23);
    for (let i = 0; i < 50; i++) a.step(50, true);
    assert.ok(a.step(0.05, false).angleTo(b.step(0.05, false)) < 1e-6);
    const initial = a.orientation.clone();
    for (let i = 0; i < 1000; i++) a.step(0.05, false);
    assert.ok(Math.abs(a.orientation.length() - 1) < 1e-9);
    assert.ok(a.orientation.angleTo(initial) > 0.2);
    const axis = a.orientation.clone().multiply(initial.invert());
    assert.ok([axis.x, axis.y, axis.z].filter(value => Math.abs(value) > 0.01).length >= 2);
    const c = new IdleRotation(7), d = new IdleRotation(7);
    assert.ok(c.step(60, false).angleTo(d.step(0.1, false)) < 1e-6);
});

test('prism light eases hover and freezes only flow with reduced motion', () => {
    const p = new PrismMotion(); p.step(0.05, true, false);
    const rising = p.engagement;
    assert.ok(rising > 0 && rising < 1);
    p.step(0.05, false, false); assert.ok(p.engagement > 0 && p.engagement < rising);
    const phase = p.phase; p.step(0.1, true, true);
    assert.equal(p.phase, phase); assert.equal(p.engagement, 1);
    p.step(0.1, false, true); assert.equal(p.engagement, 0);
    p.step(NaN, true, false); assert.equal(p.phase, phase);
    p.step(60, true, false); assert.ok(p.phase - phase < 0.01);
});
