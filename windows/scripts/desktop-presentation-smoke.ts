import assert from 'node:assert/strict';
import koffi from 'koffi';
import type { ElectronApplication, Page } from 'playwright';
import { nativeInput } from './native-input';
async function until(check:()=>Promise<boolean>,label:string):Promise<void>{const deadline=Date.now()+8000;while(Date.now()<deadline){if(await check())return;await new Promise(resolve=>setTimeout(resolve,80));}throw new Error(label);}
/** Installer smoke only: uses the already-owned receiver, never a user's application. */
export async function verifyDesktopPresentationSmoke(app:ElectronApplication,widget:Page,receiver:bigint):Promise<string[]>{
    if(process.platform!=='win32')return[];
    const settings=(await app.windows()).find(page=>page.url().endsWith('/settings.html'))!;
    assert.ok(settings,'Owned settings window missing');
    const original=await widget.evaluate(()=>window.tcube.getSnapshot());
    assert.equal(original.state.configuration.edgeCollapseEnabled,false);assert.equal(original.state.configuration.hideWhenFullscreen,false);
    const cursor=await app.evaluate(({screen})=>screen.getCursorScreenPoint());
    const native=nativeInput(),user=koffi.load('user32.dll');
    const getStyle=user.func('int32_t __stdcall GetWindowLongW(uintptr_t window, int index)');
    const setStyle=user.func('int32_t __stdcall SetWindowLongW(uintptr_t window, int index, int32_t style)');
    const position=user.func('int __stdcall SetWindowPos(uintptr_t window, uintptr_t after, int x, int y, int width, int height, uint32_t flags)');
    const getRect=user.func('int __stdcall GetWindowRect(uintptr_t window, _Out_ void *rect)');
    const activate=user.func('int __stdcall SetForegroundWindow(uintptr_t window)');
    const show=user.func('int __stdcall ShowWindow(uintptr_t window, int command)');
    const style=getStyle(receiver,-16),rect=Buffer.alloc(16);assert.ok(getRect(receiver,rect));
    const read=()=>widget.evaluate(()=>window.tcube.getSnapshot());
    const configure=async(edge:boolean,fullscreen:boolean)=>settings.evaluate(async values=>{const {state}=await window.tcube.getSnapshot();await window.tcube.applyConfiguration({...state.configuration,edgeCollapseEnabled:values.edge,hideWhenFullscreen:values.fullscreen});},{edge,fullscreen});
    const hidePanels=()=>app.evaluate(({BrowserWindow})=>{for(const window of BrowserWindow.getAllWindows())if(!window.webContents.getURL().endsWith('/widget.html'))window.hide();});
    const handles=()=>app.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows().filter(window=>window.getTitle()==='T-Cube Edge').map(window=>({visible:window.isVisible(),frame:window.getBounds()})));
    const move=async(x:number,y:number)=>{const physical=await app.evaluate(({screen},point)=>screen.dipToScreenPoint(point),{x,y});native.move(physical.x,physical.y);};
    try{
        await configure(false,false);await settings.evaluate(()=>window.tcube.place('topLeft'));await hidePanels();
        const display=await app.evaluate(({screen,BrowserWindow})=>{const window=BrowserWindow.getAllWindows().find(window=>window.webContents.getURL().endsWith('/widget.html'))!;const display=screen.getDisplayMatching(window.getBounds());return {bounds:display.bounds,work:display.workArea};});
        await move(display.work.x+display.work.width/2,display.work.y+display.work.height/2);
        await new Promise(resolve=>setTimeout(resolve,1200));assert.equal((await read()).state.visible,true);assert.equal((await handles()).length,0);
        await configure(true,false);await hidePanels();
        const resting=(await read()).state.configuration.windowPosition;
        assert.ok(resting);
        for(let cycle=0;cycle<3;cycle++){
            await until(async()=>!(await read()).state.visible,'Edge collapse missing');
            const edges=await handles();assert.equal(edges.length,1);assert.equal(edges[0].visible,true);assert.equal(edges[0].frame.width,10);assert.equal(edges[0].frame.height,56);
            assert.deepEqual((await read()).state.configuration.windowPosition,resting,'Collapsed geometry must not persist');
            const frames=await widget.evaluate(async()=>{const {controller}=await import(new URL('widget.js',location.href).href);return controller.metrics.frames;});
            await new Promise(resolve=>setTimeout(resolve,300));
            assert.equal(await widget.evaluate(async()=>{const {controller}=await import(new URL('widget.js',location.href).href);return controller.metrics.frames;}),frames,'Collapsed renderer must stop');
            await move(edges[0].frame.x+5,edges[0].frame.y+28);
            await until(async()=>(await read()).state.visible,'Edge hover did not reveal');
            await move(display.work.x+display.work.width/2,display.work.y+display.work.height/2);
        }
        await configure(false,true);await settings.evaluate(()=>window.tcube.place('center'));await hidePanels();
        await until(async()=>(await read()).state.visible,'Center should reveal');
        const physical=await app.evaluate(({screen},bounds)=>({origin:screen.dipToScreenPoint({x:bounds.x,y:bounds.y}),end:screen.dipToScreenPoint({x:bounds.x+bounds.width,y:bounds.y+bounds.height})}),display.bounds);
        setStyle(receiver,-16,style & ~0x00c40000);
        assert.ok(position(receiver,0,physical.origin.x,physical.origin.y,physical.end.x-physical.origin.x,physical.end.y-physical.origin.y,0x0020));
        activate(receiver);
        await until(async()=>!(await read()).state.visible,'Owned app fullscreen did not hide cube');
        await app.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows().find(window=>window.webContents.getURL().endsWith('/widget.html'))!.close());
        show(receiver,6); // minimize the owned fullscreen receiver
        await new Promise(resolve=>setTimeout(resolve,1300));assert.equal((await read()).state.visible,false,'Fullscreen exit must not undo manual hide');
        await settings.evaluate(()=>window.tcube.place('center'));
        await until(async()=>(await read()).state.visible,'Manual placement should reveal after fullscreen exit');
        return['Owned Windows desktop smoke: default-off controls, edge hover/three collapse cycles, single handle, no hidden rendering or position persistence, monitor-sized external fullscreen hide and manual-hide preservation passed.'];
    }finally{
        setStyle(receiver,-16,style);position(receiver,0,rect.readInt32LE(0),rect.readInt32LE(4),rect.readInt32LE(8)-rect.readInt32LE(0),rect.readInt32LE(12)-rect.readInt32LE(4),0x0030);
        show(receiver,9);
        await configure(original.state.configuration.edgeCollapseEnabled,original.state.configuration.hideWhenFullscreen);
        await settings.evaluate(()=>window.tcube.place('center'));
        await move(cursor.x,cursor.y);
        await until(async()=>(await handles()).length===0,'Disabled edge handling must release its window');
    }
}
