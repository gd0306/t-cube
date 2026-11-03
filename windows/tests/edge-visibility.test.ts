import assert from 'node:assert/strict';
import test from 'node:test';
import {EventEmitter} from 'node:events';

test('native edge visibility publishes only lifecycle changes and reload baselines, then releases listeners',async()=>{
    const {bindEdgeVisibility}=await import('../src/main/edge-visibility');
    let visible=false,destroyed=false;
    const messages:Array<{channel:string;visible:boolean}>=[];
    const contents=Object.assign(new EventEmitter(),{isDestroyed:()=>destroyed,send:(channel:string,visible:boolean)=>messages.push({channel,visible})});
    const window=Object.assign(new EventEmitter(),{isVisible:()=>visible,isDestroyed:()=>destroyed,webContents:contents});
    Object.defineProperty(window,'webContents',{get(){if(destroyed)throw Error('Destroyed native window getter is unavailable');return contents;}});
    bindEdgeVisibility(window);
    contents.emit('did-finish-load');assert.equal(messages.at(-1)?.visible,false);
    visible=true;window.emit('show');window.emit('show');assert.equal(messages.length,2);assert.equal(messages.at(-1)?.visible,true);
    contents.emit('did-finish-load');assert.equal(messages.length,3,'A replacement renderer must receive native visibility even without a window transition');
    visible=false;window.emit('hide');assert.equal(messages.at(-1)?.visible,false);
    destroyed=true;window.emit('closed');assert.equal(window.listenerCount('show'),0);assert.equal(window.listenerCount('hide'),0);assert.equal(contents.listenerCount('did-finish-load'),0);
    const count=messages.length;window.emit('show');contents.emit('did-finish-load');assert.equal(messages.length,count);
});
