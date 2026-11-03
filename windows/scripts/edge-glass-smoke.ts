import assert from 'node:assert/strict';
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
import type {ElectronApplication} from 'playwright';
export interface EdgeGlassSample {scheme:string;animations:number;active:string|undefined;hidden:boolean;nativeVisible:string|undefined;windowVisible:boolean;dataVisible:string|undefined;willChange:string}
export async function edgeGlassSample(app:ElectronApplication,id:number):Promise<EdgeGlassSample>{
    return app.evaluate(async({BrowserWindow},id)=>{const window=BrowserWindow.fromId(id)!;const renderer=await window.webContents.executeJavaScript("({scheme:getComputedStyle(document.documentElement).getPropertyValue('--edge-theme').trim(),animations:document.getAnimations().length,active:document.documentElement.dataset.animate,hidden:document.hidden,nativeVisible:document.documentElement.dataset.nativeVisible,dataVisible:document.documentElement.dataset.visible,willChange:getComputedStyle(document.querySelector('.edge-shimmer')).willChange})");return {...renderer,windowVisible:window.isVisible()};},id);
}
async function until(check:()=>Promise<boolean>,label:string):Promise<void>{const deadline=Date.now()+8000;while(Date.now()<deadline){if(await check())return;await new Promise(resolve=>setTimeout(resolve,50));}throw new Error(label);}
/** CDP emulation is scoped to this owned handle page; the user's native theme/settings are untouched. */
export async function verifyEdgeGlassMediaSmoke(app:ElectronApplication,id:number):Promise<unknown[]>{
    const attached=await app.evaluate(({BrowserWindow},id)=>{const debuggerAPI=BrowserWindow.fromId(id)!.webContents.debugger;if(debuggerAPI.isAttached())return false;debuggerAPI.attach('1.3');return true;},id);
    const media=(scheme:string,motion='no-preference',transparency='no-preference',forced='none')=>app.evaluate(async({BrowserWindow},request)=>{
        await BrowserWindow.fromId(request.id)!.webContents.debugger.sendCommand('Emulation.setEmulatedMedia',{features:[{name:'prefers-color-scheme',value:request.scheme},{name:'prefers-reduced-motion',value:request.motion},{name:'prefers-reduced-transparency',value:request.transparency},{name:'forced-colors',value:request.forced}]});
    },{id,scheme,motion,transparency,forced});
    const samples:unknown[]=[];
    try{
        for(const scheme of ['light','dark']){
            await media(scheme);await until(async()=>{const state=await edgeGlassSample(app,id);return state.scheme===scheme && state.animations===1 && state.active==='true' && !state.hidden;},`Native handle must follow ${scheme} media`);
            samples.push({media:scheme,...await edgeGlassSample(app,id)});
            const png=await app.evaluate(async({BrowserWindow},id)=>(await BrowserWindow.fromId(id)!.webContents.capturePage()).toPNG().toString('base64'),id);
            await writeFile(path.resolve(`.cache/smoke/native-edge-glass-${scheme}.png`),Buffer.from(png,'base64'));
        }
        for(const preference of ['motion','transparency','forced']){
            await media('dark',preference==='motion'?'reduce':'no-preference',preference==='transparency'?'reduce':'no-preference',preference==='forced'?'active':'none');
            await until(async()=>{const state=await edgeGlassSample(app,id);return state.animations===0 && state.active==='false' && state.willChange==='auto';},`Native handle must stop motion for ${preference}`);
            samples.push({staticPreference:preference,...await edgeGlassSample(app,id)});
        }
        await media('light');await until(async()=>(await edgeGlassSample(app,id)).animations===1,'Handle must retain exactly one animation after media cycles');
        assert.equal((await edgeGlassSample(app,id)).animations,1);
        return samples;
    }finally{
        await app.evaluate(async({BrowserWindow},request)=>{const debuggerAPI=BrowserWindow.fromId(request.id)?.webContents.debugger;if(!debuggerAPI?.isAttached())return;await debuggerAPI.sendCommand('Emulation.setEmulatedMedia',{features:[]});if(request.attached)debuggerAPI.detach();},{id,attached});
    }
}
