import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DataTexture, MeshBasicMaterial, RGBAFormat, SRGBColorSpace, Vector2 } from 'three';
import { OpticalTransition } from '../src/renderer/optical-transition';

function texture(r: number, g: number, b: number, a: number) {
    const map = new DataTexture(new Uint8Array([r, g, b, a]), 1, 1, RGBAFormat);
    map.colorSpace = SRGBColorSpace;
    return map;
}
test('optical frames retain the two texture allocations and dispose the source exactly when finished', () => {
    const material = new MeshBasicMaterial();
    const blend = new OpticalTransition(material);
    const red = texture(255, 0, 0, 255), blue = texture(0, 0, 255, 255);
    let disposed = 0;
    red.addEventListener('dispose', () => disposed++);
    blend.retarget(red, 1, false);
    blend.retarget(blue, 1, true);
    for (const progress of [0, 0.25, 0.5, 0.75]) {
        blend.update(progress);
        assert.equal(blend.uniforms.previousMap.value, red);
        assert.equal(material.map, blue);
        assert.equal(disposed, 0);
        assert.equal(blend.uniforms.themeProgress.value, progress);
    }
    blend.update(1);
    assert.equal(disposed, 1);
    assert.equal(blend.uniforms.previousMap.value, blue);
    blend.update(1);
    assert.equal(disposed, 1);
});

test('rapid optical retargeting keeps the displayed blend and releases both superseded textures', () => {
    const material = new MeshBasicMaterial(), blend = new OpticalTransition(material);
    const red = texture(255, 0, 0, 255), blue = texture(0, 0, 255, 255), green = texture(0, 255, 0, 255);
    let disposed = 0;
    red.addEventListener('dispose', () => disposed++);
    blue.addEventListener('dispose', () => disposed++);
    blend.retarget(red, 1, false);
    blend.retarget(blue, 1, true);
    blend.retarget(green, 0.5, true);
    assert.equal(disposed, 2);
    assert.deepEqual([...blend.uniforms.previousMap.value!.image.data as Uint8Array], [188, 0, 188, 255]);
    assert.equal(material.map, green);
    blend.update(0.5);
    assert.equal(blend.uniforms.themeProgress.value, 0.5);
    let released = 0;
    blend.uniforms.previousMap.value!.addEventListener('dispose', () => released++);
    green.addEventListener('dispose', () => released++);
    blend.dispose();
    assert.equal(released, 2);
    assert.equal(material.map, null);
});

test('an immediate appearance change releases an in-flight blend without retaining its source', () => {
    const material = new MeshBasicMaterial(), blend = new OpticalTransition(material);
    const red = texture(255, 0, 0, 255), blue = texture(0, 0, 255, 255), clear = texture(0, 0, 0, 0);
    let disposed = 0;
    red.addEventListener('dispose', () => disposed++);
    blue.addEventListener('dispose', () => disposed++);
    blend.retarget(red, 1, false);
    blend.retarget(blue, 1, true);
    blend.retarget(clear, 0.5, false);
    assert.equal(disposed, 2);
    assert.equal(material.map, clear);
    assert.equal(blend.uniforms.previousMap.value, clear);
    assert.equal(blend.uniforms.themeProgress.value, 1);
});

test('optical opacity belongs to each endpoint before premultiplied mixing and survives interruption', () => {
    const material = new MeshBasicMaterial(), blend = new OpticalTransition(material);
    blend.retarget(texture(255, 0, 0, 255), 1, false, 64 / 255);
    blend.retarget(texture(0, 0, 255, 64), 1, true, 1);
    assert.equal(blend.uniforms.previousOpacity.value, 64 / 255);
    assert.equal(blend.uniforms.targetOpacity.value, 1);
    blend.retarget(texture(0, 255, 0, 255), 0.5, true, 0.7);
    assert.deepEqual([...blend.uniforms.previousMap.value!.image.data as Uint8Array], [188, 0, 188, 64]);
    assert.equal(blend.uniforms.previousOpacity.value, 1);
    assert.equal(blend.uniforms.targetOpacity.value, 0.7);
});

test('retargeted optical maps preserve the displayed UV sampling before the next animation frame', () => {
    for (const animate of [false, true]) for (const matrixAutoUpdate of [false, true]) {
        const material = new MeshBasicMaterial(), blend = new OpticalTransition(material);
        const source = texture(255, 0, 0, 255), target = texture(0, 0, 255, 255);
        blend.retarget(source, 1, false);
        source.offset.set(0.0094833333, 0.012);
        source.repeat.set(0.8, 0.9);
        source.center.set(0.2, 0.3);
        source.rotation = 0.17;
        source.matrixAutoUpdate = matrixAutoUpdate;
        if (matrixAutoUpdate) source.updateMatrix();
        else source.matrix.set(1, 0.1, 0.02, 0.2, 1, 0.03, 0, 0, 1);
        const displayedUV = new Vector2(0.3, 0.4).applyMatrix3(source.matrix).toArray();

        blend.retarget(target, 1, animate);
        // Three refreshes auto matrices when drawing; manual matrices must survive unchanged.
        if (target.matrixAutoUpdate) target.updateMatrix();
        assert.deepEqual(new Vector2(0.3, 0.4).applyMatrix3(target.matrix).toArray(), displayedUV);
        assert.deepEqual(target.offset.toArray(), [0.0094833333, 0.012]);
        assert.deepEqual(target.repeat.toArray(), [0.8, 0.9]);
        assert.deepEqual(target.center.toArray(), [0.2, 0.3]);
        assert.equal(target.rotation, 0.17);
        assert.equal(target.matrixAutoUpdate, matrixAutoUpdate);
        target.offset.x = 0.2;
        assert.equal(source.offset.x, 0.0094833333, 'UV state must be copied without sharing mutable vectors');
        blend.dispose();
    }
});
