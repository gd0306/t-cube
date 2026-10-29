import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ThemeTransition, blendPremultiplied, blendTexturePixels } from '../src/core/theme-transition';
import type { Appearance } from '../src/shared/contracts';

const red: Appearance = { primaryHex: '#FF0000', secondaryHex: '#000000', glowIntensity: 0, surfaceStyle: 'clear', material: 'glass' };
const blue: Appearance = { ...red, primaryHex: '#0000FF', glowIntensity: 1, surfaceStyle: 'moonstone' };

test('theme palette starts at the old appearance and softly reaches the exact target in 400ms', () => {
    const transition = new ThemeTransition();
    transition.retarget(red, 0, false);
    assert.equal(transition.active(0), false);
    transition.retarget(blue, 1000, false);
    assert.deepEqual(transition.sample(1000).primary, [1, 0, 0]);
    assert.equal(transition.active(1399), true);
    assert.deepEqual(transition.sample(1200).primary, [0.5, 0, 0.5]);
    assert.equal(transition.sample(1200).glow, 0.5);
    assert.equal(transition.sample(1200).energy, 0.05);
    assert.deepEqual(transition.sample(1400).primary, [0, 0, 1]);
    assert.equal(transition.active(1400), false);
    assert.equal(transition.progress(1100), 0.15625);
    assert.equal(transition.progress(900), 0);
    assert.equal(transition.progress(99999), 1);
});

test('interrupted palettes start from the currently displayed blend; reduced motion and material changes finish immediately', () => {
    const transition = new ThemeTransition();
    transition.retarget(red, 0, false);
    transition.retarget(blue, 1000, false);
    transition.retarget({ ...red, primaryHex: '#00FF00' }, 1200, false);
    assert.deepEqual(transition.sample(1200).primary, [0.5, 0, 0.5]);
    assert.deepEqual(transition.sample(1400).primary, [0.25, 0.5, 0.25]);
    transition.finish();
    assert.deepEqual(transition.sample(1400).primary, [0, 1, 0]);
    assert.equal(transition.active(1400), false);
    transition.retarget(blue, 1500, true);
    assert.deepEqual(transition.sample(1500).primary, [0, 0, 1]);
    transition.retarget({ ...red, material: 'slime' }, 1600, false);
    assert.equal(transition.active(1600), false);
});

test('premultiplied blending cannot add alpha or leak invisible source color into a highlight', () => {
    assert.deepEqual(blendPremultiplied([1, 0, 0, 0], [0, 0, 1, 1], 0.5), [0, 0, 1, 0.5]);
    assert.deepEqual(blendPremultiplied([1, 0, 0, 0.25], [0, 0, 1, 0.75], 0.5), [0.25, 0, 0.75, 0.5]);
    assert.deepEqual(blendPremultiplied([1, 0, 0, 0], [0, 0, 1, 0], 0.5), [0, 0, 0, 0]);
    assert.deepEqual(blendPremultiplied([1, 0, 0, 1], [0, 0, 1, 1], 2), [0, 0, 1, 1]);
});

test('an interrupted optical map flattens once in linear light with weighted alpha', () => {
    assert.deepEqual([...blendTexturePixels(new Uint8Array([255, 0, 0, 255]), new Uint8Array([0, 0, 255, 255]), 0.5)], [188, 0, 188, 255]);
    assert.deepEqual([...blendTexturePixels(new Uint8Array([255, 0, 0, 0]), new Uint8Array([0, 0, 255, 255]), 0.5)], [0, 0, 255, 128]);
});

test('energy opacity stays within its endpoints when style and glow move in opposite directions', () => {
    const transition = new ThemeTransition();
    transition.retarget({ ...red, surfaceStyle: 'moonstone', glowIntensity: 1 }, 0, false);
    transition.retarget({ ...red, surfaceStyle: 'aurora', glowIntensity: 0.5 }, 1000, false);
    assert.equal(transition.sample(1200).energy, 0.1);
});

test('interrupted maps include endpoint opacity before blending so opposing alpha/glow cannot pulse', () => {
    const from = new Uint8Array([255, 0, 0, 255]), to = new Uint8Array([0, 0, 255, 64]);
    // Both endpoint contributions have alpha 64/255. Mixing their raw alpha and opacity separately would overshoot.
    assert.deepEqual([...blendTexturePixels(from, to, 0.5, 64 / 255, 1)], [188, 0, 188, 64]);
});
