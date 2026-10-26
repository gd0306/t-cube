import test from 'node:test';
import assert from 'node:assert/strict';
import { HoverGeometry } from '../src/core/hover';
const screens = () => [{ x: 0, y: 0, width: 1000, height: 800 }];
const fixture = () => new HoverGeometry({ x: 200, y: 200, width: 100, height: 100 }, { isEnabled: true, multiplier: 4 }, screens);

test('hover expands about the resting center and restores without persisting transient position', () => {
    const h = fixture(); let saves = 0; h.onPositionChange = () => saves++;
    h.pointerChanged({ x: 250, y: 250 });
    assert.deepEqual(h.displayFrame, { x: 50, y: 50, width: 400, height: 400 });
    h.pointerChanged({ x: 410, y: 390 }); h.setControlHeld(true);
    assert.deepEqual(h.displayFrame, { x: 320, y: 305, width: 100, height: 100 });
    h.setControlHeld(false);
    h.pointerChanged({ x: 800, y: 700 });
    assert.deepEqual(h.displayFrame, { x: 200, y: 200, width: 100, height: 100 });
    assert.equal(saves, 0);
});

test('releasing Control during a drag defers enlargement and saves the moved resting frame', () => {
    const h = fixture();
    h.pointerChanged({ x: 250, y: 250 }); h.setControlHeld(true); h.setInteractionActive(true); h.setControlHeld(false);
    assert.equal(h.displayFrame.width, 100);
    h.commitMovedFrame({ x: 240, y: 225, width: 100, height: 100 });
    h.setInteractionActive(false);
    assert.deepEqual(h.displayFrame, { x: 90, y: 75, width: 400, height: 400 });
    h.pointerChanged({ x: 800, y: 700 });
    assert.deepEqual(h.displayFrame, { x: 240, y: 225, width: 100, height: 100 });
});

test('quick placement uses resting geometry and Windows top-left coordinates on negative displays', () => {
    const h = new HoverGeometry({ x: -800, y: -200, width: 164, height: 164 }, { isEnabled: true, multiplier: 4 }, () => [{ x: -1000, y: -300, width: 1000, height: 800 }]);
    h.pointerChanged({ x: -750, y: -150 });
    h.place('topLeft');
    assert.deepEqual(h.restingFrame, { x: -976, y: -276, width: 164, height: 164 });
    h.place('bottomRight');
    assert.deepEqual(h.restingFrame, { x: -188, y: 312, width: 164, height: 164 });
    h.configure({ width: 200, height: 200 }, { isEnabled: false, multiplier: 4 });
    assert.equal(h.displayFrame.width, 200);
    assert.ok(h.displayFrame.x <= -200);
});

test('pointer exit and placement defer to an active drag, then reset restores resting geometry', () => {
    const h = fixture();
    h.pointerChanged({ x: 250, y: 250 }); h.setInteractionActive(true);
    h.pointerChanged({ x: 900, y: 700 }); h.place('bottomRight');
    assert.deepEqual(h.displayFrame, { x: 50, y: 50, width: 400, height: 400 });
    h.setInteractionActive(false);
    assert.deepEqual(h.displayFrame, { x: 200, y: 200, width: 100, height: 100 });
    h.pointerChanged({ x: 250, y: 250 }); h.setControlHeld(true); h.resetHover();
    assert.equal(h.hovered, false);
    assert.deepEqual(h.displayFrame, { x: 200, y: 200, width: 100, height: 100 });
});

test('repeated edge hover and Control shrinking do not drift the saved resting frame', () => {
    const h = new HoverGeometry({ x: 0, y: 0, width: 164, height: 164 }, { isEnabled: true, multiplier: 4 }, screens);
    for (let i = 0; i < 10; i++) {
        h.pointerChanged({ x: 30, y: 30 }); h.setControlHeld(true); h.setControlHeld(false);
        h.pointerChanged({ x: 900, y: 700 });
        assert.deepEqual(h.displayFrame, { x: 0, y: 0, width: 164, height: 164 });
    }
});
