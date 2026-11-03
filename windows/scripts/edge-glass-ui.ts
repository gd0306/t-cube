/** Production edge renderer checks with owned media/visibility fixtures; no OS theme is changed. */
import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
import {createServer} from 'node:http';
import {build} from 'esbuild';
import {chromium} from 'playwright';
const bundle=await build({entryPoints:['src/renderer/edge.ts'],bundle:true,write:false,format:'esm',platform:'browser'});
const files=new Map([['/edge.html',{mime:'text/html',body:await readFile('src/renderer/edge.html')}],['/edge.css',{mime:'text/css',body:await readFile('src/renderer/edge.css')}],['/edge.js',{mime:'text/javascript',body:Buffer.from(bundle.outputFiles[0].text)}]]);
const server=createServer((request,response)=>{const file=files.get(request.url??'');if(!file){response.writeHead(404);response.end();return;}response.writeHead(200,{'Content-Type':file.mime});response.end(file.body);});
await new Promise<void>(resolve=>server.listen(0,'127.0.0.1',resolve));
const address=server.address();assert.ok(address && typeof address!=='string');
const browser=await chromium.launch({headless:true,executablePath:process.env.TCUBE_CHROME_EXECUTABLE??(process.platform==='darwin'?'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome':undefined)});
try{
    const context=await browser.newContext({viewport:{width:32,height:56},deviceScaleFactor:3});
    const page=await context.newPage();
    await page.addInitScript(()=>{const fixture={timers:0,frames:0};(window as any).edgeFixture=fixture;const interval=window.setInterval,timeout=window.setTimeout,frame=window.requestAnimationFrame;window.setInterval=((...args:any[])=>{if(new Error().stack?.includes('/edge.js'))fixture.timers++;return (interval as any)(...args);}) as any;window.setTimeout=((...args:any[])=>{if(new Error().stack?.includes('/edge.js'))fixture.timers++;return (timeout as any)(...args);}) as any;window.requestAnimationFrame=((...args:any[])=>{if(new Error().stack?.includes('/edge.js'))fixture.frames++;return (frame as any)(...args);}) as any;});
    const cdp=await context.newCDPSession(page);
    const media=async(scheme:'light'|'dark',motion='no-preference',transparency='no-preference',forced='none')=>{await cdp.send('Emulation.setEmulatedMedia',{features:[{name:'prefers-color-scheme',value:scheme},{name:'prefers-reduced-motion',value:motion},{name:'prefers-reduced-transparency',value:transparency},{name:'forced-colors',value:forced}]});};
    const sample=()=>page.evaluate(()=>{const root=getComputedStyle(document.documentElement),capsule=document.querySelector<HTMLElement>('.edge-capsule')!,style=getComputedStyle(capsule),rect=capsule.getBoundingClientRect();return {scheme:root.getPropertyValue('--edge-theme').trim(),background:style.backgroundImage,rect:{x:rect.x,y:rect.y,width:rect.width,height:rect.height},animations:document.getAnimations().length,active:document.documentElement.dataset.animate,visible:document.documentElement.dataset.visible,fixture:(window as any).edgeFixture};});
    await media('light');await page.goto(`http://127.0.0.1:${address.port}/edge.html`);await page.waitForFunction(()=>document.documentElement.dataset.animate==='true');
    const light=await sample();assert.equal(light.scheme,'light');assert.deepEqual(light.rect,{x:1,y:2,width:8,height:52});assert.equal(light.animations,1);
    await mkdir('.cache/smoke',{recursive:true});await page.screenshot({path:'.cache/smoke/edge-glass-light.png',omitBackground:true});
    await media('dark');await page.waitForFunction(()=>getComputedStyle(document.documentElement).getPropertyValue('--edge-theme').trim()==='dark');
    const dark=await sample();assert.notEqual(dark.background,light.background);assert.equal(dark.animations,1);await page.screenshot({path:'.cache/smoke/edge-glass-dark.png',omitBackground:true});
    await media('dark','reduce');await page.waitForFunction(()=>document.getAnimations().length===0 && document.documentElement.dataset.animate==='false');assert.equal((await sample()).active,'false');
    await media('dark','no-preference','reduce');await page.waitForFunction(()=>document.getAnimations().length===0 && document.documentElement.dataset.animate==='false');assert.equal((await sample()).active,'false');
    await media('light','no-preference','no-preference','active');await page.waitForFunction(()=>document.getAnimations().length===0);
    await media('light');await page.waitForFunction(()=>document.getAnimations().length===1);
    for(let cycle=0;cycle<4;cycle++){
        await page.evaluate(()=>window.dispatchEvent(new PageTransitionEvent('pagehide')));assert.equal((await sample()).animations,0);
        await page.evaluate(()=>window.dispatchEvent(new PageTransitionEvent('pageshow')));assert.equal((await sample()).animations,1);
    }
    await page.evaluate(()=>window.dispatchEvent(new PageTransitionEvent('pagehide')));
    const before=await sample();await new Promise(resolve=>setTimeout(resolve,300));const hidden=await sample();assert.equal(hidden.animations,0);assert.deepEqual(hidden.fixture,before.fixture);
    assert.deepEqual(hidden.fixture,{timers:0,frames:0},'Edge renderer must schedule no JavaScript timer/frame loop');
    console.log('Actual edge renderer: OS light/dark changes,8x52capsule, reduced motion/transparency/forced colors, hidden cancellation, repeated lifecycle and zeroJS timer/frame loops passed.');
}finally{await browser.close();await new Promise<void>(resolve=>server.close(()=>resolve()));}
