/** Production renderer + real recorder/operations; owned fixtures, no system clipboard or native Windows claims. */
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {chromium} from 'playwright';
import {mkdir,readFile} from 'node:fs/promises';
import {ClipboardHistoryRecorder,clipboardHistoryOperations} from '../src/main/clipboard-history';
const bundled=await build({stdin:{contents:"export {ClipboardQuickPanel} from './src/renderer/clipboard-quick';",resolveDir:process.cwd()},bundle:true,write:false,format:'iife',globalName:'Quick',platform:'browser'});
const browser=await chromium.launch({headless:true,executablePath:process.env.TCUBE_CHROME_EXECUTABLE??(process.platform==='darwin'?'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome':undefined)});
const page=await browser.newPage({viewport:{width:380,height:520}});
let sequence=1,content:any='Original text',copies=0,dismissals=0,failCopy=false;
const recorder=new ClipboardHistoryRecorder({sequence:()=>sequence,read:async()=>content},state=>{void page.evaluate(state=>(window as any).changed?.(state),state);},()=>()=>{});
const operations=clipboardHistoryOperations(recorder,async()=>{if(failCopy)throw Error('owned failure');copies++;return {status:'copied'};},async()=>{copies++;return {status:'copied'};});
await page.exposeFunction('operation',async(name:string,value:any)=>{
    if(name==='dismissClipboardQuick'){dismissals++;return;}
    if(name==='copyClipboardQuickEntry'){await operations.useClipboardHistoryEntry({id:value,paste:false});dismissals++;return;}
    return operations[name](value);
});
try {
    await page.setContent('<main id="root"></main>'); await page.addScriptTag({content:'window.__name=value=>value;'});
    await page.addStyleTag({content:await readFile('src/renderer/clipboard-quick.css','utf8')});
    await page.addScriptTag({content:bundled.outputFiles[0].text});
    await page.evaluate(()=>{
        const g=window as any,bridge:any={onClipboardHistoryChanged:(callback:any)=>{g.changed=callback;return()=>{};}};
        for(const name of ['getClipboardHistory','setClipboardHistoryEnabled','editClipboardHistoryEntry','deleteClipboardHistoryEntry','copyClipboardQuickEntry','dismissClipboardQuick','showClipboardHistory'])bridge[name]=(value:any)=>g.operation(name,value);
        g.panel=new g.Quick.ClipboardQuickPanel(document.querySelector('#root'),bridge);
    });
    await page.getByRole('button',{name:'启用记录',exact:true}).click(); assert.equal(recorder.state.isEnabled,true); assert.equal(recorder.state.entries.length,0);
    sequence++;await recorder.poll();
    await page.getByRole('button',{name:'编辑文字',exact:true}).click();
    await page.getByRole('textbox',{name:'编辑历史文字',exact:true}).fill('Cancelled draft');
    await page.getByRole('button',{name:'取消',exact:true}).click(); assert.equal(recorder.state.entries[0].text,'Original text');
    await page.getByRole('button',{name:'编辑文字',exact:true}).click();
    await page.getByRole('textbox',{name:'编辑历史文字',exact:true}).fill('   ');
    await page.getByRole('button',{name:'保存',exact:true}).click();
    await page.getByRole('status').filter({hasText:'未完成'}).waitFor();
    assert.equal(await page.getByRole('textbox',{name:'编辑历史文字',exact:true}).evaluate(element=>element===document.activeElement),true);
    assert.equal(recorder.state.entries[0].text,'Original text');
    await page.getByRole('textbox',{name:'编辑历史文字',exact:true}).fill('Edited text');
    sequence++;content='New arrival';await recorder.poll();
    assert.equal(await page.getByRole('textbox',{name:'编辑历史文字',exact:true}).inputValue(),'Edited text');
    await page.getByRole('button',{name:'保存',exact:true}).click();
    await page.waitForFunction(()=>!document.querySelector('textarea'));
    assert.deepEqual(recorder.state.entries.map(entry=>entry.text),['New arrival','Edited text']);assert.equal(copies,0);assert.equal(dismissals,0);
    failCopy=true; await page.getByRole('button',{name:'复制文字：Edited text',exact:true}).click();
    await page.getByRole('status').filter({hasText:'未完成'}).waitFor(); assert.equal(dismissals,0);
    failCopy=false;await page.getByRole('button',{name:'复制文字：Edited text',exact:true}).click();
    await page.waitForTimeout(80);assert.equal(copies,1);assert.equal(dismissals,1);
    content={png:Buffer.from('owned PNG'),width:1,height:1,thumbnail:'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=='};sequence++;await recorder.poll();
    await page.getByRole('button',{name:'复制图片：1 × 1',exact:true}).click();await page.waitForTimeout(80);assert.equal(copies,2);
    await page.getByRole('button',{name:'删除图片',exact:true}).click();await page.waitForFunction(()=>!document.querySelector('.quick-thumbnail'));assert.equal(recorder.state.images?.length,0);
    await mkdir('.cache/smoke',{recursive:true});
    await page.screenshot({path:'.cache/smoke/clipboard-quick-light.png'});
    await page.evaluate(()=>{document.documentElement.style.background='linear-gradient(110deg,#0d253d 0%,#90a7bd 50%,#ffe9cf 100%)';});
    await page.screenshot({path:'.cache/smoke/clipboard-quick-light-owned-backdrop.png'});
    await page.evaluate(()=>{document.documentElement.style.background='';});
    await page.emulateMedia({colorScheme:'dark'});await page.screenshot({path:'.cache/smoke/clipboard-quick-dark.png'});
    await page.evaluate(()=>{document.documentElement.style.background='linear-gradient(110deg,#0d253d 0%,#90a7bd 50%,#ffe9cf 100%)';});
    await page.screenshot({path:'.cache/smoke/clipboard-quick-dark-owned-backdrop.png'});
    await page.evaluate(()=>{document.documentElement.style.background='';});
    await page.getByRole('button',{name:'编辑文字',exact:true}).first().click();
    await page.getByRole('textbox',{name:'编辑历史文字',exact:true}).fill('Removed draft');
    operations.deleteClipboardHistoryEntry(recorder.state.entries[0].id);
    await page.waitForFunction(()=>!document.querySelector('textarea'));
    await page.getByRole('button',{name:'编辑文字',exact:true}).click();
    await page.getByRole('textbox',{name:'编辑历史文字',exact:true}).fill('Cleared draft');
    operations.clearClipboardHistory();await page.waitForFunction(()=>!document.querySelector('textarea'));
    assert.equal(recorder.state.entries.length,0);
    console.log('Quick history production UI + recorder: opt-in, draft cancel/preservation/save, copy/error/dismiss, image copy/delete passed.');
}finally{recorder.dispose();await browser.close();}
