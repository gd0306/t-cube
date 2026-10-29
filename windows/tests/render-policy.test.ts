import {test} from 'node:test';
import assert from 'node:assert/strict';
import {animationCadence, type RenderActivity} from '../src/core/render-policy';
const idle:RenderActivity={visible:true,documentVisible:true,hovered:false,interacting:false,reducedMotion:false,autoRotates:true,idlePowerSaving:true,slimeActive:false,settling:false,glow:1};
test('enabled power saving stops idle timers even when rotation and glow are configured',()=>{
    assert.equal(animationCadence(idle),0);
    assert.equal(animationCadence({...idle,idlePowerSaving:false}),15);
});
test('interaction and rebound remain responsive, hidden and reduced motion never spin',()=>{
    assert.equal(animationCadence({...idle,hovered:true}),30);
    assert.equal(animationCadence({...idle,slimeActive:true}),30);
    assert.equal(animationCadence({...idle,settling:true}),30);
    assert.equal(animationCadence({...idle,visible:false,hovered:true}),0);
    assert.equal(animationCadence({...idle,documentVisible:false,hovered:true}),0);
    assert.equal(animationCadence({...idle,reducedMotion:true,slimeActive:true}),0);
});
test('a finite theme transition wakes office idle at 30Hz and releases it when finished',()=>{
    assert.equal(animationCadence({...idle,themeTransition:true}),30);
    assert.equal(animationCadence({...idle,themeTransition:false}),0);
    assert.equal(animationCadence({...idle,themeTransition:true,reducedMotion:true}),0);
    assert.equal(animationCadence({...idle,themeTransition:true,documentVisible:false}),0);
});
