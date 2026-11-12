/** Windows CI only: real SendInput Ctrl hold and production quick UI, inside the outer owned clipboard snapshot. */
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {release as osRelease} from 'node:os';
import {mkdir,writeFile} from 'node:fs/promises';
import path from 'node:path';
import koffi from 'koffi';
import type {ElectronApplication,Page} from 'playwright';
import {nativeInput} from './native-input';

async function until(check:()=>Promise<boolean>,label:string):Promise<void> {
    const deadline=performance.now()+8000;
    while(performance.now()<deadline){
        if(await check())return;
        await new Promise(resolve=>setTimeout(resolve,60));
    }
    throw new Error(label);
}
/** Observation window proves absence over time; it never retries a gesture or action. */
async function remains(check:()=>Promise<void>,milliseconds:number):Promise<void> {
    const deadline=performance.now()+milliseconds;
    do{await check();await new Promise(resolve=>setTimeout(resolve,80));}while(performance.now()<deadline);
}

export async function verifyClipboardQuickSmoke(app:ElectronApplication,widget:Page,library:Page,
    activateOwnedReceiver:()=>Promise<void>,readOwnedReceiver:()=>string,stage:(name:string)=>Promise<void>):Promise<string[]> {
    if(process.platform!=='win32')return[];
    const isolation=await app.evaluate(({app})=>({actual:app.getPath('userData'),expected:process.env.TCUBE_USER_DATA_DIR}));
    assert.ok(isolation.expected,'Native quick-history smoke requires isolated CI data');
    assert.equal(path.resolve(isolation.actual),path.resolve(isolation.expected));
    const state=()=>library.evaluate(()=>window.tcube.getClipboardHistory());
    const initial=await state();
    assert.equal(initial.isEnabled,true,'Session recording must remain enabled after owned history smoke');
    assert.equal(initial.entries.length,0,'Native quick-history smoke only permits its own fixture history');
    assert.equal(initial.images?.length??0,0);
    const native=nativeInput(),user=koffi.load('user32.dll');
    const key=user.func('int16_t __stdcall GetAsyncKeyState(int key)');
    const widgetFrame=()=>app.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows()
        .find(window=>window.webContents.getURL().endsWith('/widget.html'))!.getBounds());
    const movePointer=async(point:{x:number;y:number})=>{
        const physical=await app.evaluate(({screen},point)=>screen.dipToScreenPoint(point),point);
        native.move(physical.x,physical.y);
    };
    const moveOutside=async()=>{
        const point=await app.evaluate(({BrowserWindow,screen})=>{
            const frame=BrowserWindow.getAllWindows().find(window=>window.webContents.getURL().endsWith('/widget.html'))!.getBounds();
            const candidates=screen.getAllDisplays().flatMap(display=>{
                const r=display.workArea;
                return [{x:r.x+2,y:r.y+2},{x:r.x+r.width-3,y:r.y+2},
                    {x:r.x+2,y:r.y+r.height-3},{x:r.x+r.width-3,y:r.y+r.height-3}];
            });
            return candidates.find(p=>p.x<frame.x||p.y<frame.y||p.x>=frame.x+frame.width||p.y>=frame.y+frame.height);
        });
        assert.ok(point,'Native Ctrl smoke needs a pointer position outside the actual cube window');
        await movePointer(point);
        await until(async()=>!(await widget.evaluate(()=>window.tcube.getSnapshot())).state.hovered,'Pointer did not leave the cube');
    };

    const quickState=()=>app.evaluate(({BrowserWindow})=>{
        const window=BrowserWindow.getAllWindows().find(window=>window.webContents.getURL().endsWith('/clipboard-quick.html'));
        return {exists:Boolean(window),visible:window?.isVisible()??false,loading:window?.webContents.isLoading()??false,id:window?.id};
    });
    const diagnostics:unknown[]=[];
    const record=async(name:string,extra:Record<string,unknown>={})=>{
        const history=await state();
        const entry={stage:name,controlHeld:Boolean(key(0x11)&0x8000),quick:await quickState(),enabled:history.isEnabled,
            textCount:history.entries.length,imageCount:history.images?.length??0,receiverUnchanged:readOwnedReceiver()===receiverBefore,...extra};
        diagnostics.push(entry);console.log(`Quick history native: ${JSON.stringify(entry)}`);
        await mkdir(path.resolve('.cache/smoke'),{recursive:true});
        await writeFile(path.resolve('.cache/smoke/clipboard-quick-native.json'),JSON.stringify(diagnostics,null,2));
    };
    const text=`T-Cube owned quick history ${randomUUID()}`;
    const edited=`${text}\nEdited through native quick UI`;
    const receiverBefore=readOwnedReceiver();
    let failure:unknown;
    try{
        await stage('quick history: prepare owned fixture');
        const prepared=await quickState();
        assert.equal(prepared.exists,true,'Quick renderer must be prepared before the first hold');
        assert.equal(prepared.loading,false,'The first hold must not pay a cold renderer load');
        assert.equal(prepared.visible,false,'Prewarming must never show the panel');
        await widget.evaluate(()=>window.tcube.showClipboardHistory());
        assert.equal((await state()).isEnabled,true,'Opening quick history must retain the startup recording default');
        await app.evaluate(async({clipboard},text)=>clipboard.writeText(text),text);
        await until(async()=>{const value=await state();return value.entries.length===1&&value.entries[0].text===text;},'Owned quick-history fixture was not recorded');
        const original=(await state()).entries[0];
        // Transfer foreground from the active Electron process before hiding its library window.
        await activateOwnedReceiver();
        native.control(false);
        await moveOutside();
        await remains(async()=>assert.equal((await quickState()).visible,false,'Quick history must be hidden before native input'),300);

        await stage('quick history: short Ctrl does not open');
        native.control(true);
        await until(async()=>Boolean(key(0x11)&0x8000),'SendInput Ctrl-down was not observed in native key state');
        await remains(async()=>assert.equal((await quickState()).visible,false,'Short Ctrl opened quick history'),300);
        native.control(false);
        await remains(async()=>assert.equal((await quickState()).visible,false,'Released short Ctrl later opened quick history'),1100);
        await record('short press stayed hidden');

        await stage('quick history: hover Ctrl restores size without opening history');
        await activateOwnedReceiver();
        const resting=await widgetFrame();
        await movePointer({x:resting.x+resting.width/2,y:resting.y+resting.height/2});
        await until(async()=>(await widgetFrame()).width>resting.width,'Hover must enlarge before Ctrl arbitration');
        native.control(true);
        await until(async()=>(await widgetFrame()).width===resting.width,'Ctrl must restore the cube resting size');
        await remains(async()=>{
            assert.equal((await quickState()).visible,false,'Hover Ctrl opened quick history');
            assert.equal((await widgetFrame()).width,resting.width,'Held Ctrl lost resting geometry');
        },1200);
        await moveOutside();
        await remains(async()=>assert.equal((await quickState()).visible,false,'Leaving the cube rearmed the same Ctrl hold'),1200);
        native.control(false);
        await until(async()=>!(key(0x11)&0x8000),'Hover Ctrl did not release');
        await record('hover Ctrl reserved through restoring size and leaving');

        await stage('quick history: entering the cube cancels an outside hold');
        native.control(true);
        await remains(async()=>assert.equal((await quickState()).visible,false,'Outside hold opened before one second'),300);
        const frame=await widgetFrame();
        await movePointer({x:frame.x+frame.width/2,y:frame.y+frame.height/2});
        await until(async()=>(await widget.evaluate(()=>window.tcube.getSnapshot())).state.hovered,'Held Ctrl did not enter the cube');
        await moveOutside();
        await remains(async()=>assert.equal((await quickState()).visible,false,'Entering then leaving rearmed the same Ctrl hold'),1200);
        native.control(false);
        await until(async()=>!(key(0x11)&0x8000),'Entering-cube Ctrl did not release');
        await record('entering cube cancelled the whole outside hold');

        await stage('quick history: fresh outside Ctrl hold opens after one second');
        await activateOwnedReceiver();
        await moveOutside();
        const started=performance.now();
        native.control(true);
        await until(async()=>Boolean(key(0x11)&0x8000),'Native long-press Ctrl-down was not observed');
        await until(async()=>(await quickState()).visible,'Holding native Ctrl outside for one second did not open quick history');
        const elapsed=performance.now()-started;
        assert.equal((await quickState()).id,prepared.id,'The hold must reuse the already loaded quick window');
        assert.ok(elapsed<=1250,`Warm quick history exceeded its 250 ms display budget (${Math.round(elapsed)} ms)`);
        assert.ok(elapsed>=1000,`Quick history opened before one second (${Math.round(elapsed)} ms)`);
        native.control(false);
        await until(async()=>!(key(0x11)&0x8000),'Ctrl was not released after activation');
        await remains(async()=>assert.equal((await quickState()).visible,true,'Releasing Ctrl must retain quick history'),350);
        await record('long press opened and release retained',{elapsedMilliseconds:Math.round(elapsed)});
        const quick=app.windows().find(page=>page.url().endsWith('/clipboard-quick.html'));
        assert.ok(quick,'Native Ctrl must create the actual production quick-history page');
        await stage('quick history: native title drag and frosted backing');
        const beforeDrag=await app.evaluate(({BrowserWindow})=>{
            const window=BrowserWindow.getAllWindows().find(window=>window.webContents.getURL().endsWith('/clipboard-quick.html'))!;
            return {bounds:window.getBounds(),movable:window.isMovable(),background:window.getBackgroundColor()};
        });
        assert.equal(beforeDrag.movable,true);
        const title=await quick.locator('header h1').boundingBox();assert.ok(title);
        const area=await app.evaluate(({screen},bounds)=>screen.getDisplayMatching(bounds).workArea,beforeDrag.bounds);
        const dx=beforeDrag.bounds.x+beforeDrag.bounds.width+80<area.x+area.width?80:-80;
        const dy=beforeDrag.bounds.y+beforeDrag.bounds.height+40<area.y+area.height?40:-40;
        const start={x:beforeDrag.bounds.x+title.x+title.width/2,y:beforeDrag.bounds.y+title.y+title.height/2};
        await movePointer(start);native.button(0,true);
        try {
            for(let step=1;step<=8;step++){
                await movePointer({x:start.x+dx*step/8,y:start.y+dy*step/8});
                await new Promise(resolve=>setTimeout(resolve,25));
            }
        } finally {native.button(0,false);}
        await until(async()=>{
            const frame=await app.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows().find(window=>window.webContents.getURL().endsWith('/clipboard-quick.html'))!.getBounds());
            return Math.abs(frame.x-beforeDrag.bounds.x)>=40;
        },'Dragging the actual quick-window title did not move the native window');
        assert.equal((await quickState()).visible,true,'Title dragging must not dismiss the quick panel');
        const build=Number(osRelease().split('.')[2]);
        if(build<22621)assert.notEqual(beforeDrag.background.toLowerCase(),'#00000000','Older Windows must have a solid fallback rather than a transparent desktop window');
        await record('native title drag moved panel',{before:beforeDrag.bounds});
        await stage('quick history: per-record preview and explicit result editing');
        const textTools=quick.getByRole('combobox',{name:'快捷处理文字',exact:true});
        await textTools.click();await quick.keyboard.press('Home');
        for(let step=0;step<4;step++)await quick.keyboard.press('ArrowDown');
        await quick.keyboard.press('Enter');
        await quick.getByText('转为大写 · 预览',{exact:true}).waitFor();
        assert.equal((await quickState()).visible,true,'Native processing menu must not dismiss the panel');
        await activateOwnedReceiver();
        await moveOutside();native.control(false);native.control(true);
        await until(async()=>(await quickState()).visible,'Fresh Ctrl hold did not reopen quick history');
        native.control(false);
        await until(async()=>await textTools.count()===1,'A fresh hold must show the list, not the previous preview');
        assert.equal(await quick.getByText('转为大写 · 预览',{exact:true}).count(),0);
        await textTools.selectOption('uppercase');
        await quick.getByText('转为大写 · 预览',{exact:true}).waitFor();
        assert.deepEqual((await state()).entries,[original],'Generating a preview must preserve the original record');
        assert.equal(await app.evaluate(async({clipboard})=>clipboard.readText()),text,'Generating a preview must not write the clipboard');
        await quick.getByRole('button',{name:'编辑结果',exact:true}).click();
        await quick.getByRole('textbox',{name:'编辑处理结果',exact:true}).fill('Edited processing preview');
        await quick.getByRole('button',{name:'保存到本条记录',exact:true}).click();
        await until(async()=>(await state()).entries[0]?.text==='Edited processing preview','Explicit result save did not update the record');
        assert.equal((await state()).entries[0].copiedAt,original.copiedAt);
        assert.equal(await app.evaluate(async({clipboard})=>clipboard.readText()),text,'Saving a processing result must not write the clipboard');
        await quick.getByRole('button',{name:'编辑文字',exact:true}).click();
        await quick.getByRole('textbox',{name:'编辑历史文字',exact:true}).fill(edited);
        await stage('quick history: edit and save through quick UI');
        await quick.getByRole('button',{name:'保存',exact:true}).click();
        await until(async()=>{const value=await state();return value.entries.length===1&&value.entries[0].text===edited;},'Quick UI edit did not save');
        const saved=await state();
        assert.deepEqual(saved.entries,[{...original,text:edited}],'Editing must preserve identity, copied time and order');
        assert.equal(await app.evaluate(async({clipboard})=>clipboard.readText()),text,'Editing history must not change the system clipboard');
        await record('edit saved without clipboard write');
        const png=await app.evaluate(async({BrowserWindow})=>{
            const window=BrowserWindow.getAllWindows().find(window=>window.webContents.getURL().endsWith('/clipboard-quick.html'))!;
            return (await window.webContents.capturePage()).toPNG().toString('base64');
        });
        await writeFile(path.resolve('.cache/smoke/clipboard-quick-native.png'),Buffer.from(png,'base64'));

        await stage('quick history: click copies edited text and hides');
        await quick.getByRole('button',{name:'复制文字：'+edited.replace(/\s+/g,' '),exact:true}).click();
        await until(async()=>!(await quickState()).visible,'Successful quick copy did not hide the panel');
        assert.equal(await app.evaluate(async({clipboard})=>clipboard.readText()),edited,'Quick click must copy the edited fixture');
        await remains(async()=>{
            assert.deepEqual((await state()).entries,saved.entries,'Quick self-copy must not be captured again or promote the history entry');
        },1100); // More than two 500 ms recorder intervals.
        assert.equal(readOwnedReceiver(),receiverBefore,'Quick copy must not paste or type into the owned receiver');
        await record('copied and hidden without self-recording');
        return ['Native Windows SendInput: short Ctrl stayed hidden; hover Ctrl restored size without opening history, leaving or entering the cube kept that press cancelled, and a fresh outside one-second Ctrl hold opened quick history with release retention. Native title dragging moved the frosted panel; per-record processing preview and explicit editing preserved clipboard and timestamps. Actual quick UI edited/saved without clipboard writes, then copied/closed without duplicate recording or receiver input. Automated desktop input, not a manual check.'];
    }catch(error){
        failure=error;
        await record('failure').catch(()=>{});
        throw error;
    }finally{
        const cleanupErrors:unknown[]=[];
        try{native.control(false);}catch(error){cleanupErrors.push(error);}
        try{await app.evaluate(({BrowserWindow})=>{
            for(const window of BrowserWindow.getAllWindows())if(window.webContents.getURL().endsWith('/clipboard-quick.html'))window.hide();
        });}catch(error){cleanupErrors.push(error);}
        try{await library.evaluate(async enabled=>{await window.tcube.setClipboardHistoryEnabled(enabled);await window.tcube.clearClipboardHistory();},initial.isEnabled);}catch(error){cleanupErrors.push(error);}
        if(cleanupErrors.length){const error=new AggregateError(cleanupErrors,'Native quick-history smoke cleanup failed');if(failure)console.error(error);else throw error;}
    }
}
