/** Production edge renderer checks with owned media/visibility fixtures; no OS theme is changed. */
import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
import {createServer} from 'node:http';
import {build} from 'esbuild';
import {chromium} from 'playwright';
const bundle=await build({entryPoints:['src/renderer/edge.ts'],bundle:true,write:false,format:'esm',platform:'browser'});
const files=new Map([['/edge.html',{mime:'text/html',body:await readFile('src/renderer/edge.html')}],['/edge.css',{mime:'text/css',body:await readFile('src/renderer/edge.css')}],['/edge.js',{mime:'text/javascript',body:Buffer.from(bundle.outputFiles[0].text)}]]);
const server=createServer((request,response)=>{const file=files.get((request.url??'').split('?')[0]);if(!file){response.writeHead(404);response.end();return;}response.writeHead(200,{'Content-Type':file.mime});response.end(file.body);});
await new Promise<void>(resolve=>server.listen(0,'127.0.0.1',resolve));
const address=server.address();assert.ok(address && typeof address!=='string');
const browser=await chromium.launch({headless:true,executablePath:process.env.TCUBE_CHROME_EXECUTABLE??(process.platform==='darwin'?'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome':undefined)});
try{
    const context=await browser.newContext({viewport:{width:32,height:56},deviceScaleFactor:3});
    const page=await context.newPage();
    await context.addInitScript(()=>{if(!location.search.includes('without-host')){const callbacks=new Set<(visible:boolean)=>void>();let visible=true;(window as any).tcubeEdge={onVisibility(callback:(value:boolean)=>void){callbacks.add(callback);callback(visible);return()=>callbacks.delete(callback);}};(window as any).edgeNativeFixture={setVisible(value:boolean){visible=value;for(const callback of callbacks)callback(value);}};}const fixture={timers:0,frames:0};(window as any).edgeFixture=fixture;const interval=window.setInterval,timeout=window.setTimeout,frame=window.requestAnimationFrame;window.setInterval=((...args:any[])=>{if(new Error().stack?.includes('/edge.js'))fixture.timers++;return (interval as any)(...args);}) as any;window.setTimeout=((...args:any[])=>{if(new Error().stack?.includes('/edge.js'))fixture.timers++;return (timeout as any)(...args);}) as any;window.requestAnimationFrame=((...args:any[])=>{if(new Error().stack?.includes('/edge.js'))fixture.frames++;return (frame as any)(...args);}) as any;});
    const cdp=await context.newCDPSession(page);
    const media=async(scheme:'light'|'dark',motion='no-preference',transparency='no-preference',forced='none')=>{await cdp.send('Emulation.setEmulatedMedia',{features:[{name:'prefers-color-scheme',value:scheme},{name:'prefers-reduced-motion',value:motion},{name:'prefers-reduced-transparency',value:transparency},{name:'forced-colors',value:forced}]});};
    const sample=()=>page.evaluate(()=>{const root=getComputedStyle(document.documentElement),capsule=document.querySelector<HTMLElement>('.edge-capsule')!,style=getComputedStyle(capsule),rect=capsule.getBoundingClientRect();return {scheme:root.getPropertyValue('--edge-theme').trim(),background:style.backgroundImage,rect:{x:rect.x,y:rect.y,width:rect.width,height:rect.height},animations:document.getAnimations().length,active:document.documentElement.dataset.animate,visible:document.documentElement.dataset.visible,fixture:(window as any).edgeFixture};});
    await media('light');await page.goto(`http://127.0.0.1:${address.port}/edge.html`);await page.waitForFunction(()=>document.documentElement.dataset.animate==='true');
    const light=await sample();assert.equal(light.scheme,'light');assert.deepEqual(light.rect,{x:1,y:2,width:8,height:52});assert.equal(light.animations,1);
    const verifyWholeReflection = async (scheme: 'light' | 'dark') => {
        for (const phase of [0, .25, .5, .75, 1]) {
            const coverage = await page.evaluate(phase => {
                const animation = document.getAnimations()[0]; animation.pause();
                animation.currentTime = Number(animation.effect!.getTiming().duration) * phase;
                const shimmer = document.querySelector<HTMLElement>('.edge-shimmer')!, capsule = document.querySelector('.edge-capsule')!;
                const a = shimmer.getBoundingClientRect(), b = capsule.getBoundingClientRect();
                return {coversEnds: a.top <= b.top && a.bottom >= b.bottom, opacity: Number(getComputedStyle(shimmer).opacity)};
            }, phase);
            assert.ok(coverage.coversEnds && coverage.opacity >= .1, `Whole-length reflection must remain visible at ${scheme} phase ${phase}: ${JSON.stringify(coverage)}`);
            // Inspect the actual browser screenshot; transparent gradient stops must fail too.
            const png = (await page.screenshot({omitBackground:true})).toString('base64');
            const pixels = await page.evaluate(async png => {
                const bytes = Uint8Array.from(atob(png), c => c.charCodeAt(0));
                const bitmap = await createImageBitmap(new Blob([bytes], {type:'image/png'}));
                const canvas = document.createElement('canvas'); canvas.width = bitmap.width; canvas.height = bitmap.height;
                const context = canvas.getContext('2d')!; context.drawImage(bitmap,0,0); bitmap.close();
                const rect = document.querySelector('.edge-capsule')!.getBoundingClientRect(), scale = canvas.width / innerWidth;
                return [.12,.5,.88].map(fraction => {
                    const pixel = context.getImageData(Math.floor((rect.x+rect.width/2)*scale), Math.floor((rect.y+rect.height*fraction)*scale),1,1).data;
                    return {brightness:(pixel[0]+pixel[1]+pixel[2])/765, alpha:pixel[3]/255};
                });
            }, png);
            for (const pixel of pixels) assert.ok(pixel.alpha > .05 && pixel.alpha < .48,
                `${scheme} glass must transmit most background content at phase ${phase}: ${JSON.stringify(pixels)}`);
            for (const end of [pixels[0],pixels[2]]) assert.ok(end.brightness > (scheme==='dark'?.16:.7) && end.brightness > pixels[1].brightness*.45,
                `Both ${scheme} ends must retain reflection at phase ${phase}: ${JSON.stringify(pixels)}`);
        }
        const backgrounds: number[] = [];
        for (const color of ['black','white']) {
            await page.evaluate(color => {document.body.style.background = color;}, color);
            const png = (await page.screenshot()).toString('base64');
            backgrounds.push(await page.evaluate(async png => {
                const bitmap = await createImageBitmap(new Blob([Uint8Array.from(atob(png), c=>c.charCodeAt(0))], {type:'image/png'}));
                const canvas = document.createElement('canvas'); canvas.width=bitmap.width; canvas.height=bitmap.height;
                const context = canvas.getContext('2d')!; context.drawImage(bitmap,0,0); bitmap.close();
                const rect = document.querySelector('.edge-capsule')!.getBoundingClientRect(), scale=canvas.width/innerWidth;
                const pixel=context.getImageData(Math.floor((rect.x+rect.width/2)*scale),Math.floor((rect.y+rect.height/2)*scale),1,1).data;
                return (pixel[0]+pixel[1]+pixel[2])/765;
            }, png));
        }
        assert.ok(backgrounds[1]-backgrounds[0]>.52, `${scheme} glass must preserve changing background contrast: ${backgrounds}`);
        await page.evaluate(() => {document.body.style.background='transparent';});
        await page.evaluate(() => document.getAnimations()[0].play());
    };
    await verifyWholeReflection('light');
    await mkdir('.cache/smoke',{recursive:true});await page.screenshot({path:'.cache/smoke/edge-glass-light.png',omitBackground:true});
    await media('dark');await page.waitForFunction(()=>getComputedStyle(document.documentElement).getPropertyValue('--edge-theme').trim()==='dark');
    const dark=await sample();assert.notEqual(dark.background,light.background);assert.equal(dark.animations,1);await verifyWholeReflection('dark');await page.screenshot({path:'.cache/smoke/edge-glass-dark.png',omitBackground:true});
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
    const missing=await context.newPage();await missing.goto(`http://127.0.0.1:${address.port}/edge.html?without-host`);
    const missingState=await missing.evaluate(()=>{const capsule=document.querySelector('.edge-capsule')!,rect=capsule.getBoundingClientRect();return {hasBridge:Boolean((window as any).tcubeEdge),hidden:document.hidden,active:document.documentElement.dataset.animate,animations:document.getAnimations().length,background:getComputedStyle(capsule).backgroundImage,width:rect.width,height:rect.height};});
    assert.equal(missingState.hasBridge,false);assert.equal(missingState.hidden,false);assert.equal(missingState.active,'false','Missing host visibility authority must fail closed');assert.equal(missingState.animations,0);assert.notEqual(missingState.background,'none');assert.equal(missingState.width,8);assert.equal(missingState.height,52);
    await missing.close();
    console.log('Actual edge renderer: OS light/dark changes,8x52capsule, reduced motion/transparency/forced colors, hidden cancellation, repeated lifecycle zeroJS timer/frame loops and missing-host static fallback passed.');
}finally{await browser.close();await new Promise<void>(resolve=>server.close(()=>resolve()));}
