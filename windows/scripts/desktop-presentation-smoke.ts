import assert from 'node:assert/strict';
import koffi from 'koffi';
import type { ElectronApplication, Page } from 'playwright';
import { nativeInput } from './native-input';
import {edgeHandle} from '../src/core/desktop-presentation';
import {mkdir,writeFile} from 'node:fs/promises';
import path from 'node:path';
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
    const dpi=user.func('uint32_t __stdcall GetDpiForWindow(uintptr_t window)');
    const getClientRect=user.func('int __stdcall GetClientRect(uintptr_t window, _Out_ void *rect)');
    const windowRegion=user.func('int __stdcall GetWindowRgn(uintptr_t window, uintptr_t region)');
    const fromPoint=user.func('uintptr_t __stdcall WindowFromPoint(int64_t point)');
    const ancestor=user.func('uintptr_t __stdcall GetAncestor(uintptr_t window, uint32_t flag)');
    const gdi=koffi.load('gdi32.dll');
    const createRegion=gdi.func('uintptr_t __stdcall CreateRectRgn(int left, int top, int right, int bottom)');
    const regionBox=gdi.func('int __stdcall GetRgnBox(uintptr_t region, _Out_ void *rect)');
    const deleteObject=gdi.func('int __stdcall DeleteObject(uintptr_t object)');
    const getRect=user.func('int __stdcall GetWindowRect(uintptr_t window, _Out_ void *rect)');
    const activate=user.func('int __stdcall SetForegroundWindow(uintptr_t window)');
    const show=user.func('int __stdcall ShowWindow(uintptr_t window, int command)');
    const style=getStyle(receiver,-16),rect=Buffer.alloc(16);assert.ok(getRect(receiver,rect));
    const read=()=>widget.evaluate(()=>window.tcube.getSnapshot());
    const configure=async(edge:boolean,fullscreen:boolean)=>settings.evaluate(async values=>{const {state}=await window.tcube.getSnapshot();await window.tcube.applyConfiguration({...state.configuration,edgeCollapseEnabled:values.edge,hideWhenFullscreen:values.fullscreen});},{edge,fullscreen});
    const hidePanels=()=>app.evaluate(({BrowserWindow})=>{for(const window of BrowserWindow.getAllWindows())if(!window.webContents.getURL().endsWith('/widget.html'))window.hide();});
    const handles=()=>app.evaluate(({BrowserWindow,screen})=>BrowserWindow.getAllWindows().filter(window=>window.getTitle()==='T-Cube Edge').map(window=>({id:window.id,visible:window.isVisible(),frame:window.getBounds(),content:window.getContentBounds(),minimum:window.getMinimumSize(),maximum:window.getMaximumSize(),scaleFactor:screen.getDisplayMatching(window.getBounds()).scaleFactor,nativeHandle:window.getNativeWindowHandle().toString('hex')})));
    const decodeHandle=(hex:string)=>{const bytes=Buffer.from(hex,'hex');return bytes.length===8?bytes.readBigUInt64LE():BigInt(bytes.readUInt32LE());};
    const rectValue=(bytes:Buffer)=>({x:bytes.readInt32LE(0),y:bytes.readInt32LE(4),width:bytes.readInt32LE(8)-bytes.readInt32LE(0),height:bytes.readInt32LE(12)-bytes.readInt32LE(4)});
    const windowAt=(x:number,y:number)=>{const point=Buffer.alloc(8);point.writeInt32LE(x);point.writeInt32LE(y,4);return BigInt(ancestor(fromPoint(point.readBigInt64LE()),2));};
    const nativeGeometry=(hex:string)=>{
        const handle=decodeHandle(hex),bounds=Buffer.alloc(16),client=Buffer.alloc(16),region=Buffer.alloc(16),rgn=createRegion(0,0,0,0);
        try{assert.ok(getRect(handle,bounds));assert.ok(getClientRect(handle,client));const regionType=windowRegion(handle,rgn);if(regionType)assert.ok(regionBox(rgn,region));
            const frame=rectValue(bounds),shape=regionType?rectValue(region):null;
            const absolute=shape?{...shape,x:frame.x+shape.x,y:frame.y+shape.y}:null;
            const inside=absolute?windowAt(absolute.x+Math.floor(absolute.width/2),absolute.y+Math.floor(absolute.height/2))===handle:null;
            const outside=shape?(shape.x>0?{x:frame.x+shape.x-1,y:frame.y+shape.y+Math.floor(shape.height/2)}:{x:frame.x+shape.x+shape.width+1,y:frame.y+shape.y+Math.floor(shape.height/2)}):null;
            return {frame,client:rectValue(client),dpi:dpi(handle),regionType,shape,absolute,insideHit:inside,outsideHit:outside?windowAt(outside.x,outside.y)===handle:null};
        }finally{deleteObject(rgn);}
    };
    const diagnostics:unknown[]=[];
    const saveDiagnostics=async()=>{await mkdir(path.resolve('.cache/smoke'),{recursive:true});await writeFile(path.resolve('.cache/smoke/desktop-edge-diagnostics.json'),JSON.stringify(diagnostics,null,2));};
    const probeMinimums=async()=>{
        for(const explicit of [false,true]){
            const id=await app.evaluate(({BrowserWindow,screen},explicit)=>{const work=screen.getPrimaryDisplay().workArea;const window=new BrowserWindow({title:'T-Cube owned edge size probe',x:work.x,y:work.y+100,width:10,height:56,...(explicit?{minWidth:10,maxWidth:10,minHeight:56,maxHeight:56}:{}),show:false,frame:false,transparent:true,resizable:false,focusable:false,thickFrame:false,hasShadow:false,skipTaskbar:true,webPreferences:{sandbox:true,nodeIntegration:false,contextIsolation:true}});window.setMenu(null);window.setBounds({x:work.x,y:work.y+100,width:10,height:56});window.showInactive();return window.id;},explicit);
            try{const electron=await app.evaluate(({BrowserWindow,screen},id)=>{const window=BrowserWindow.fromId(id)!;return {frame:window.getBounds(),content:window.getContentBounds(),minimum:window.getMinimumSize(),maximum:window.getMaximumSize(),scaleFactor:screen.getDisplayMatching(window.getBounds()).scaleFactor,nativeHandle:window.getNativeWindowHandle().toString('hex')};},id);diagnostics.push({probe:explicit?'explicit-min-max':'original-options',requested:{width:10,height:56},electron,native:nativeGeometry(electron.nativeHandle)});}
            finally{await app.evaluate(({BrowserWindow},id)=>BrowserWindow.fromId(id)?.destroy(),id);}
        }
        await saveDiagnostics();
    };
    const move=async(x:number,y:number)=>{const physical=await app.evaluate(({screen},point)=>screen.dipToScreenPoint(point),{x,y});native.move(physical.x,physical.y);};
    try{
        await probeMinimums();
        await configure(false,false);await settings.evaluate(()=>window.tcube.place('topLeft'));await hidePanels();
        const display=await app.evaluate(({screen,BrowserWindow})=>{const window=BrowserWindow.getAllWindows().find(window=>window.webContents.getURL().endsWith('/widget.html'))!;const display=screen.getDisplayMatching(window.getBounds());return {bounds:display.bounds,work:display.workArea};});
        await move(display.work.x+display.work.width/2,display.work.y+display.work.height/2);
        await new Promise(resolve=>setTimeout(resolve,1200));assert.equal((await read()).state.visible,true);assert.equal((await handles()).length,0);
        await configure(true,false);await hidePanels();
        let resting=(await read()).state.configuration.windowPosition;
        assert.ok(resting);
        for(let cycle=0;cycle<4;cycle++){
            if(cycle===3){await settings.evaluate(()=>window.tcube.place('topRight'));await hidePanels();resting=(await read()).state.configuration.windowPosition;assert.ok(resting);}
            await until(async()=>!(await read()).state.visible,'Edge collapse missing');
            await until(async()=>{const edges=await handles();return edges.length===1 && edges[0].visible;},'Loaded edge handle did not become visible');
            const edges=await handles();assert.equal(edges.length,1);assert.equal(edges[0].visible,true);
            const geometry=nativeGeometry(edges[0].nativeHandle);
            const displayFrames=await app.evaluate(({screen})=>screen.getAllDisplays().map(display=>({work:display.workArea,bounds:display.bounds})));
            const expected=edgeHandle({...resting,width:164*(await read()).state.configuration.scale,height:164*(await read()).state.configuration.scale},displayFrames.map(display=>display.work),displayFrames.map(display=>display.bounds));assert.ok(expected);
            const expectedPixels=await app.evaluate(({screen},frame)=>screen.dipToScreenRect(null,frame),expected);
            const visual=await app.evaluate(async({BrowserWindow},id)=>{const window=BrowserWindow.fromId(id)!;return window.webContents.executeJavaScript("(()=>{const rect=document.querySelector('div').getBoundingClientRect();return {x:rect.x,y:rect.y,width:rect.width,height:rect.height,viewportWidth:innerWidth,viewportHeight:innerHeight};})()");},edges[0].id) as {x:number;y:number;width:number;height:number;viewportWidth:number;viewportHeight:number};
            diagnostics.push({cycle,requested:expected,expectedPixels,electron:edges[0],visual,native:geometry});await saveDiagnostics();
            assert.equal(visual.width,6);assert.equal(visual.height,48);
            assert.ok(visual.x>=0 && visual.y>=0 && visual.x+visual.width<=visual.viewportWidth && visual.y+visual.height<=visual.viewportHeight,'Visible bar must fit the actual renderer content');
            if(cycle===0 || cycle===3){const png=await app.evaluate(async({BrowserWindow},id)=>(await BrowserWindow.fromId(id)!.webContents.capturePage()).toPNG().toString('base64'),edges[0].id);await writeFile(path.resolve(`.cache/smoke/desktop-edge-${cycle===0?'left':'right'}.png`),Buffer.from(png,'base64'));}
            assert.ok(Math.abs(edges[0].frame.x+visual.x-expected.x-2)<=1,'Visible bar must remain inside the10px handle on either edge');
            assert.ok(geometry.absolute,'Native edge region must be set');
            for(const key of ['x','y','width','height'] as const)assert.ok(Math.abs(geometry.absolute[key]-expectedPixels[key])<=1,`Native10x56 edge region mismatch: ${key}`);
            assert.equal(geometry.insideHit,true,'Handle hit region must receive the pointer');assert.equal(geometry.outsideHit,false,'Transparent container outside10px handle must pass the pointer through');
            assert.deepEqual((await read()).state.configuration.windowPosition,resting,'Collapsed geometry must not persist');
            const frames=await widget.evaluate(async()=>{const {controller}=await import(new URL('widget.js',location.href).href);return controller.metrics.frames;});
            await new Promise(resolve=>setTimeout(resolve,300));
            assert.equal(await widget.evaluate(async()=>{const {controller}=await import(new URL('widget.js',location.href).href);return controller.metrics.frames;}),frames,'Collapsed renderer must stop');
            await move(expected.x+5,expected.y+28);
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
        return['Owned Windows desktop smoke: default-off controls, edge hover/left-right collapse cycles, single handle, no hidden rendering or position persistence, monitor-sized external fullscreen hide and manual-hide preservation passed.'];
    }finally{
        await saveDiagnostics();
        setStyle(receiver,-16,style);position(receiver,0,rect.readInt32LE(0),rect.readInt32LE(4),rect.readInt32LE(8)-rect.readInt32LE(0),rect.readInt32LE(12)-rect.readInt32LE(4),0x0030);
        show(receiver,9);
        await configure(original.state.configuration.edgeCollapseEnabled,original.state.configuration.hideWhenFullscreen);
        await settings.evaluate(()=>window.tcube.place('center'));
        await move(cursor.x,cursor.y);
        await until(async()=>(await handles()).length===0,'Disabled edge handling must release its window');
    }
}
