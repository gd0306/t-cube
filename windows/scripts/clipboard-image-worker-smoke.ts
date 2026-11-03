/** Runs in a disposable Electron main process; no clipboard or user files are accessed. */
import assert from 'node:assert/strict';
import {app,BrowserWindow} from 'electron';
import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {ClipboardImageProcessor} from '../src/main/clipboard-image';
app.on('window-all-closed',()=>{});
void app.whenReady().then(async()=>{
app.dock?.hide();
const processor=new ClipboardImageProcessor(path.resolve('dist/renderer'));
try{
    const small=await processor.normalize(await readFile('assets/icon.png'),()=>true);assert.ok(small);
    const fixture=await readFile('.cache/smoke/owned-16mp.png');
    let beats=0;const timer=setInterval(()=>{beats++;},2);
    const large=await processor.normalize(fixture,()=>true);clearInterval(timer);assert.ok(large);assert.equal(large.width*large.height,16_000_000);assert.ok(beats>5,'Main must remain responsive during codec work');
    assert.equal(BrowserWindow.getAllWindows().length,1,'Only one lazy processor window is retained');
    const active=processor.normalize(fixture,()=>true),stale=processor.preview(large,()=>true),newest=processor.preview(small,()=>true);
    assert.equal(await stale,null,'Only newest pending work is retained');assert.ok(await active);assert.ok(await newest);
    const captureA=processor.normalize(fixture,()=>true),captureB=processor.normalize(small.png,()=>true),previewC=processor.preview(small,()=>true);
    assert.ok(await captureA);assert.ok(await captureB,'Preview must not replace the newest pending recording');assert.ok(await previewC);
    let current=true;
    const canceled=processor.normalize(fixture,()=>current);current=false;processor.cancel();assert.equal(await canceled,null);
    assert.equal(BrowserWindow.getAllWindows().length,0,'Cancel releases native renderer/window');
    assert.ok(await processor.normalize(await readFile('assets/icon.png'),()=>true));
    processor.dispose();assert.equal(BrowserWindow.getAllWindows().length,0);
    console.log(`Owned16MP processor: off-main codec responsiveness (${beats} main-loop samples), single active/newest pending, cancel and window release passed.`);
}finally{processor.dispose();app.quit();}

}).catch(error=>{console.error(error);app.exit(1);});
