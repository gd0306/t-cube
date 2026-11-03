/** Disposable Electron fixture: actual hidden/show/hidden lifecycle without global theme or clipboard changes. */
import assert from 'node:assert/strict';
import {app,BrowserWindow} from 'electron';
import path from 'node:path';
import type {ElectronApplication} from 'playwright';
import {verifyEdgeGlassMediaSmoke} from './edge-glass-smoke';
app.on('window-all-closed',()=>{});
void app.whenReady().then(async()=>{
    app.dock?.hide();
    const window=new BrowserWindow({show:false,paintWhenInitiallyHidden:false,width:32,height:56,frame:false,transparent:true,focusable:false,skipTaskbar:true,webPreferences:{sandbox:true,nodeIntegration:false,contextIsolation:true}});
    window.setMenu(null);
    const sample=()=>window.webContents.executeJavaScript("({hidden:document.hidden,active:document.documentElement.dataset.animate,animations:document.getAnimations().length,willChange:getComputedStyle(document.querySelector('.edge-shimmer')).willChange})") as Promise<{hidden:boolean;active:string;animations:number;willChange:string}>;
    const until=async(check:()=>Promise<boolean>)=>{const deadline=Date.now()+5000;while(Date.now()<deadline){if(await check())return;await new Promise(resolve=>setTimeout(resolve,30));}throw Error('Owned edge lifecycle did not settle');};
    try{
        await window.loadFile(path.resolve('dist/renderer/edge.html'));
        await window.webContents.executeJavaScript("document.querySelector('div').style.transform='translate(22px,0px)'");
        assert.equal(await window.webContents.executeJavaScript("document.querySelector('div').getBoundingClientRect().x"),23,'Native right-container translation must work with the local page CSP');
        assert.deepEqual(await sample(),{hidden:true,active:'false',animations:0,willChange:'auto'});
        window.webContents.debugger.attach('1.3');
        await window.webContents.debugger.sendCommand('Emulation.setEmulatedMedia',{features:[{name:'prefers-reduced-motion',value:'no-preference'},{name:'prefers-reduced-transparency',value:'no-preference'},{name:'forced-colors',value:'none'}]});
        for(let cycle=0;cycle<4;cycle++){
            window.showInactive();await until(async()=>{const state=await sample();return !state.hidden && state.animations===1 && state.active==='true';});
            window.hide();await until(async()=>{const state=await sample();return state.hidden && state.animations===0 && state.active==='false' && state.willChange==='auto';});
        }
        window.showInactive();
        const ownedApp={evaluate:(operation:(electron:{BrowserWindow:typeof BrowserWindow},value:unknown)=>unknown,value:unknown)=>Promise.resolve(operation({BrowserWindow},value))} as unknown as ElectronApplication;
        const mediaSamples=await verifyEdgeGlassMediaSmoke(ownedApp,window.id);assert.equal(mediaSamples.length,5);
        window.hide();await until(async()=>(await sample()).animations===0);
        console.log('Actual Electron edge: initially hidden without animation; four show/hide cycles retain one visible animation and cancel hidden animations/compositor hints; private native media/contrast/static fallbacks and right-container CSP translation passed.');
    }finally{window.destroy();app.quit();}
}).catch(error=>{console.error(error);app.exit(1);});
