import test from 'node:test';
import assert from 'node:assert/strict';
import { HoverGeometry } from '../src/core/hover';
const screens = () => [{ x: 0, y: 0, width: 1000, height: 800 }];
const fixture = () => new HoverGeometry({ x: 200, y: 200, width: 100, height: 100 }, { isEnabled: true, multiplier: 4, delaySeconds: 0 }, screens);

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
    const h = new HoverGeometry({ x: -800, y: -200, width: 164, height: 164 }, { isEnabled: true, multiplier: 4, delaySeconds: 0 }, () => [{ x: -1000, y: -300, width: 1000, height: 800 }]);
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
    const h = new HoverGeometry({ x: 0, y: 0, width: 164, height: 164 }, { isEnabled: true, multiplier: 4, delaySeconds: 0 }, screens);
    for (let i = 0; i < 10; i++) {
        h.pointerChanged({ x: 30, y: 30 }); h.setControlHeld(true); h.setControlHeld(false);
        h.pointerChanged({ x: 900, y: 700 });
        assert.deepEqual(h.displayFrame, { x: 0, y: 0, width: 164, height: 164 });
    }
});


test('hover waits for continuous dwell and Control shrinks immediately while pending', () => {
    let now = 0;
    const h = new HoverGeometry({ x: 200, y: 200, width: 100, height: 100 }, { isEnabled: true, multiplier: 4, delaySeconds: 0.18 }, screens, () => now);
    h.pointerChanged({ x: 250, y: 250 });
    assert.equal(h.hovered, false);
    now = 0.17; h.tick(); assert.equal(h.displayFrame.width, 100);
    now = 0.18; h.tick(); assert.equal(h.displayFrame.width, 400);
    h.resetHover(); h.pointerChanged({ x: 250, y: 250 });
    h.setControlHeld(true); assert.equal(h.hovered, true); assert.equal(h.displayFrame.width, 100);
    h.setControlHeld(false); assert.equal(h.hovered, false);
    now += 0.18; h.tick(); assert.equal(h.displayFrame.width, 400);
});

test('exit, dragging, configuration and restoration cancel pending hover without saving positions', () => {
    let now = 0, saves = 0;
    const settings = { isEnabled: true, multiplier: 4, delaySeconds: 0.2 };
    const h = new HoverGeometry({ x: 200, y: 200, width: 100, height: 100 }, settings, screens, () => now);
    h.onUserPositionCommit = () => saves++;
    h.pointerChanged({ x: 250, y: 250 }); now = 0.1; h.pointerChanged({ x: 800, y: 700 });
    now = 0.3; h.tick(); assert.equal(h.hovered, false);
    h.pointerChanged({ x: 250, y: 250 }); h.setInteractionActive(true); now = 1; h.tick(); h.setInteractionActive(false);
    assert.equal(h.hovered, false);
    h.configure({ width: 110, height: 110 }, settings); now = 2; h.tick(); assert.equal(h.hovered, false);
    h.restoreRestingFrame({ x: 300, y: 300 }); now = 3; h.tick(); assert.equal(h.hovered, false);
    assert.equal(saves, 0);
});

test('hover multiplier fits the selected work area and preserves aspect ratio', () => {
    const h = new HoverGeometry({ x: 100, y: 100, width: 164, height: 164 }, { isEnabled: true, multiplier: 4, delaySeconds: 0 }, () => [{ x: 0, y: 0, width: 300, height: 250 }]);
    h.pointerChanged({ x: 150, y: 150 });
    assert.deepEqual(h.displayFrame, { x: 50, y: 0, width: 250, height: 250 });
});
