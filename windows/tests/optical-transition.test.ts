import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DataTexture, MeshBasicMaterial, RGBAFormat, SRGBColorSpace } from 'three';
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
