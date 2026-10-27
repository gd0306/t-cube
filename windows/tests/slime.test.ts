import test from 'node:test';
import assert from 'node:assert/strict';
import { Vector3 } from 'three';
import { SlimeDeformation, SlimeMotion } from '../src/core/slime';

const near = new Vector3(0, 0, 0.5);

test('rest leaves the surface unchanged and deformation reuses caller-owned output vectors', () => {
    const deformation = new SlimeDeformation();
    const point = new Vector3(0.2, -0.3, 0.5);
    const normal = new Vector3(0, 0, 1);
    const target = new Vector3();
    assert.deepEqual(deformation.position(point).toArray(), point.toArray());
    assert.deepEqual(deformation.normal(normal, point).toArray(), normal.toArray());
    assert.equal(deformation.position(point, target), target);
    assert.deepEqual(point.toArray(), [0.2, -0.3, 0.5]);
    assert.equal(deformation.normal(normal, point, target), target);
    assert.deepEqual(normal.toArray(), [0, 0, 1]);
    deformation.pull = 0.1;
    deformation.shear.set(0.02, -0.01, 0);
    assert.ok(deformation.position(near, target).distanceTo(new Vector3(0.02, -0.01, 0.597)) < 1e-12);
    const inPlace = near.clone();
    assert.equal(deformation.position(inPlace, inPlace), inPlace);
    assert.ok(inPlace.distanceTo(target) < 1e-12);
});

test('bent-surface normals remain perpendicular to the deformed surface tangents', () => {
    const deformation = new SlimeDeformation();
    deformation.contact.set(0.2, -0.1, 0.5);
    deformation.pull = 0.13;
    deformation.shear.set(-0.04, 0.03, 0.01);
    const point = new Vector3(0.35, 0.15, 0.5);
    const normal = new Vector3(0, 0, 1);
    const bentNormal = deformation.normal(normal, point);
    assert.ok(Math.abs(bentNormal.length() - 1) < 1e-12);
    assert.ok(bentNormal.distanceTo(normal) > 0.02);
    for (const direction of [new Vector3(1, 0, 0), new Vector3(0, 1, 0)]) {
        const before = deformation.position(point.clone().addScaledVector(direction, -0.00001));
        const after = deformation.position(point.clone().addScaledVector(direction, 0.00001));
        assert.ok(Math.abs(bentNormal.dot(after.sub(before).normalize())) < 1e-8);
    }
});

test('contact pulls nearby surface while release rebounds and settles exactly at rest', () => {
    const motion = new SlimeMotion();
    assert.equal(motion.isActive, false);
    motion.setContact(near);
    assert.equal(motion.isActive, true);
    for (let index = 0; index < 30; index++) motion.step(1 / 60, false);
    assert.ok(motion.deformation.position(near).z > 0.56);
    const far = new Vector3(0, 0, -0.5);
    assert.ok(motion.deformation.position(far).distanceTo(far) < 0.03);
    motion.setContact(null);
    let crossedRest = false;
    for (let index = 0; index < 240; index++) {
        motion.step(1 / 60, false);
        crossedRest ||= motion.deformation.pull < 0;
    }
    assert.equal(crossedRest, true);
    assert.equal(motion.deformation.pull, 0);
    assert.deepEqual(motion.deformation.position(near).toArray(), near.toArray());
    assert.equal(motion.isActive, false);
});

test('fast contact motion creates bounded shear and lag before settling at the new point', () => {
    const motion = new SlimeMotion();
    motion.setContact(new Vector3(-0.4, 0, 0.45));
    for (let index = 0; index < 40; index++) motion.step(1 / 60, false);
    motion.setContact(new Vector3(0.4, 0, 0.45));
    motion.step(1 / 60, false);
    assert.ok(motion.deformation.shear.length() > 0.01);
    assert.ok(motion.deformation.shear.length() <= 0.09);
    assert.ok(motion.deformation.contact.x < 0.3);
    for (let index = 0; index < 90; index++) motion.step(1 / 60, false);
    const point = new Vector3(0.4, 0, 0.45);
    assert.ok(motion.deformation.position(point).x > point.x);
    assert.ok(motion.deformation.contact.distanceTo(point) < 0.00001);
    assert.ok(motion.deformation.shear.length() < 0.001);
});

test('invalid times leave motion untouched and a long paused frame advances only the bounded interval', () => {
    const motion = new SlimeMotion();
    motion.setContact(near);
    motion.step(0.05, false);
    assert.ok(motion.deformation.pull > 0);
    const before = motion.deformation.position(near);
    for (const time of [NaN, Infinity, -Infinity, -1, 0]) {
        motion.step(time, false);
        assert.deepEqual(motion.deformation.position(near), before);
    }
    const bounded = new SlimeMotion();
    bounded.setContact(near);
    bounded.step(0.05, false);
    bounded.step(0.05, false);
    motion.step(600, false);
    assert.deepEqual(motion.deformation.position(near), bounded.deformation.position(near));
    assert.ok(Math.abs(motion.deformation.pull) < 0.18);
});

test('reduced motion clears pull, shear, velocity, and pending contact', () => {
    const motion = new SlimeMotion();
    motion.setContact(new Vector3(-0.4, 0, 0.45));
    motion.step(0.05, false);
    motion.setContact(new Vector3(0.4, 0, 0.45));
    motion.step(0.05, false);
    assert.ok(motion.deformation.shear.length() > 0);
    motion.step(0.05, true);
    assert.deepEqual(motion.deformation.position(near).toArray(), near.toArray());
    assert.equal(motion.isActive, false);
    motion.step(0.05, false);
    assert.equal(motion.isActive, false);
});

test('contact copies and bounds valid points while invalid points release existing motion', () => {
    const motion = new SlimeMotion();
    const contact = new Vector3(2, -2, 0.5);
    motion.setContact(contact);
    assert.deepEqual(motion.deformation.contact.toArray(), [0.7, -0.7, 0.5]);
    contact.set(0, 0, -0.5);
    for (let index = 0; index < 90; index++) motion.step(1 / 60, false);
    assert.deepEqual(motion.deformation.contact.toArray(), [0.7, -0.7, 0.5]);
    for (const invalid of [new Vector3(NaN, 0, 0.5), new Vector3(0, Infinity, 0.5), new Vector3(0, 0, 0), new Vector3(0.05, 0, 0)]) {
        const resting = new SlimeMotion();
        resting.setContact(invalid);
        assert.equal(resting.isActive, false);
        motion.setContact(near);
        motion.step(0.05, false);
        motion.setContact(invalid);
        for (let index = 0; index < 240; index++) motion.step(1 / 60, false);
        assert.equal(motion.isActive, false);
    }
});
