/** Windows CI only: real SendInput Ctrl hold and production quick UI, inside the outer owned clipboard snapshot. */
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
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
    assert.equal(initial.isEnabled,false,'Previous owned history smoke must leave recording paused');
    assert.equal(initial.entries.length,0,'Native quick-history smoke only permits its own fixture history');
    assert.equal(initial.images?.length??0,0);
    const native=nativeInput(),user=koffi.load('user32.dll');
    const key=user.func('int16_t __stdcall GetAsyncKeyState(int key)');
    const quickState=()=>app.evaluate(({BrowserWindow})=>{
        const window=BrowserWindow.getAllWindows().find(window=>window.webContents.getURL().endsWith('/clipboard-quick.html'));
        return {exists:Boolean(window),visible:window?.isVisible()??false};
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
        await widget.evaluate(()=>window.tcube.showClipboardHistory());
        await library.getByRole('button',{name:/^(启用|恢复)记录$/}).click();
        await until(async()=>(await state()).isEnabled,'History recording did not explicitly enable');
        await app.evaluate(async({clipboard},text)=>clipboard.writeText(text),text);
        await until(async()=>{const value=await state();return value.entries.length===1&&value.entries[0].text===text;},'Owned quick-history fixture was not recorded');
        const original=(await state()).entries[0];
        await app.evaluate(({BrowserWindow},url)=>BrowserWindow.getAllWindows().find(window=>window.webContents.getURL()===url)?.hide(),library.url());
        await activateOwnedReceiver();
        native.control(false);
        await remains(async()=>assert.equal((await quickState()).visible,false,'Quick history must be hidden before native input'),300);

        await stage('quick history: short Ctrl does not open');
        native.control(true);
        await until(async()=>Boolean(key(0x11)&0x8000),'SendInput Ctrl-down was not observed in native key state');
        await remains(async()=>assert.equal((await quickState()).visible,false,'Short Ctrl opened quick history'),300);
        native.control(false);
        await remains(async()=>assert.equal((await quickState()).visible,false,'Released short Ctrl later opened quick history'),2100);
        await record('short press stayed hidden');

        await stage('quick history: native Ctrl hold opens after two seconds');
        await activateOwnedReceiver();
        const started=performance.now();
        native.control(true);
        await until(async()=>Boolean(key(0x11)&0x8000),'Native long-press Ctrl-down was not observed');
        await until(async()=>(await quickState()).visible,'Holding native Ctrl for two seconds did not open quick history');
        const elapsed=performance.now()-started;
        assert.ok(elapsed>=2000,`Quick history opened before two seconds (${Math.round(elapsed)} ms)`);
        native.control(false);
        await until(async()=>!(key(0x11)&0x8000),'Ctrl was not released after activation');
        await remains(async()=>assert.equal((await quickState()).visible,true,'Releasing Ctrl must retain quick history'),350);
        await record('long press opened and release retained',{elapsedMilliseconds:Math.round(elapsed)});
        const quick=app.windows().find(page=>page.url().endsWith('/clipboard-quick.html'));
        assert.ok(quick,'Native Ctrl must create the actual production quick-history page');
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
        return ['Native Windows SendInput: short Ctrl stayed hidden; a two-second Ctrl hold opened quick history and release retained it. Actual quick UI edited/saved without clipboard writes, then copied/closed without duplicate recording or receiver input. Automated desktop input, not a manual check.'];
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
