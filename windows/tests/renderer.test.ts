import { test } from 'node:test';
import assert from 'node:assert/strict';
import { padTransparentRGB, wheelDelta } from '../src/renderer/util';

test('transparent padding extends color without changing coverage', () => {
    const data = new Uint8ClampedArray(5 * 4);
    data.set([100, 150, 200, 255], 8);
    padTransparentRGB(data, 5, 1, 1);
    assert.deepEqual(
        Array.from(data),
        [0, 0, 0, 0, 100, 150, 200, 0, 100, 150, 200, 255, 100, 150, 200, 0, 0, 0, 0, 0],
    );
});
test('wheel maps Chrome vertical and shift wheel to native axes', () => {
    assert.deepEqual(wheelDelta(0, 3, false, 0), { dx: 0, dy: -3, precise: true });
    assert.deepEqual(wheelDelta(0, 1, true, 1), { dx: -1, dy: 0, precise: false });
});
