import assert from 'node:assert/strict';
import test from 'node:test';
import { ControlHoldGesture } from '../src/core/control-hold';

const input = (held: boolean, interrupted = false) => ({available:true,controlHeld:held,interrupted});
function advance(gesture: ControlHoldGesture, start: number, end: number): boolean {
    for (let time=start+200;time<end;time+=200) assert.equal(gesture.update(input(true),time),false);
    return gesture.update(input(true),end);
}
test('a fresh lone Ctrl hold triggers once after two seconds and release does not dismiss it', () => {
    const gesture = new ControlHoldGesture();
    assert.equal(gesture.update(input(false),0),false); gesture.update(input(true),10);
    assert.equal(advance(gesture,10,2009),false);
    assert.equal(gesture.update(input(true),2010),true);
    assert.equal(gesture.update(input(true),2500),false);
    assert.equal(gesture.update(input(false),2600),false);
    gesture.update(input(true),2700); assert.equal(advance(gesture,2700,4700),true);
});
test('any interference blocks the entire hold until release, including drag, wheel and shortcuts', () => {
    const gesture = new ControlHoldGesture(); gesture.update(input(false),0); gesture.update(input(true),10);
    gesture.interrupt(); assert.equal(advance(gesture,10,2010),false);
    gesture.update(input(false),2020); gesture.update(input(true,true),2030);
    assert.equal(advance(gesture,2030,4030),false);
    gesture.update(input(false),4040); gesture.update(input(true),4050); assert.equal(advance(gesture,4050,6050),true);
});
test('startup held Ctrl, unavailable input, clock gaps and resume require a fresh release', () => {
    for (const interrupt of ['startup','unavailable','gap','reset']) {
        const gesture = new ControlHoldGesture();
        if (interrupt !== 'startup') { gesture.update(input(false),0); gesture.update(input(true),10); }
        if (interrupt === 'unavailable') gesture.update({...input(true),available:false},20);
        if (interrupt === 'reset') gesture.reset();
        assert.equal(gesture.update(input(true),10000),false,interrupt);
        gesture.update(input(false),10010); gesture.update(input(true),10020);
        assert.equal(advance(gesture,10020,12020),true);
    }
});
test('a shortcut entirely between polling samples still cancels the upcoming hold', () => {
    const gesture = new ControlHoldGesture(); gesture.update(input(false),0);
    gesture.interrupt(); gesture.update(input(true),100);
    assert.equal(advance(gesture,100,2100),false);
});
