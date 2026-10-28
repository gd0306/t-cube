import test from 'node:test';
import assert from 'node:assert/strict';
import { rememberDisplayPosition, restoreDisplayPosition, normalizeDisplayPositionMemory } from '../src/core/display-placement';
const primary = { id: 'primary', workArea: { x: 0, y: 0, width: 1000, height: 800 } };
const left = { id: 'left', workArea: { x: -1000, y: -200, width: 1000, height: 800 } };
const frame = { x: -600, y: 100, width: 200, height: 200 };
test('display memory restores normalized coordinates after display geometry changes', () => {
    const memory = rememberDisplayPosition({ version: 1, activeDisplayId: null, positions: {} }, frame, [primary, left]);
    assert.equal(memory.activeDisplayId, 'left');
    assert.deepEqual(memory.positions.left, { x: 0.5, y: 0.5 });
    assert.deepEqual(restoreDisplayPosition(memory, { width: 200, height: 200 }, [primary, { id: 'left', workArea: { x: -1800, y: 0, width: 1800, height: 1200 } }], frame), { x: -1000, y: 500 });
});
test('disconnect falls back to primary while preserving disconnected memory for reconnection', () => {
    const memory = rememberDisplayPosition({ version: 1, activeDisplayId: null, positions: {} }, frame, [primary, left]);
    const original = structuredClone(memory);
    assert.deepEqual(restoreDisplayPosition(memory, frame, [primary], frame), { x: 0, y: 100 });
    assert.deepEqual(memory, original);
    assert.deepEqual(restoreDisplayPosition(memory, frame, [primary, left], frame), { x: -600, y: 100 });
});
test('display memory rejects malformed, nonfinite and unbounded coordinates', () => {
    for (const positions of [{ left: { x: -0.1, y: 0 } }, { left: { x: 1.1, y: 0 } }, { left: { x: NaN, y: 0 } }, { left: { x: 0, y: Infinity } }]) {
        assert.throws(() => normalizeDisplayPositionMemory({ version: 1, activeDisplayId: 'left', positions }));
    }
});
