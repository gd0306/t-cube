// Isolated renderer acceptance: no native clipboard writes and no user history.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { build } from 'esbuild';
import { chromium } from 'playwright';
const fixture = await build({stdin: {contents: `
import { ClipboardQuickPanel } from './src/renderer/clipboard-quick';
import { ClipboardHistoryPanel } from './src/renderer/clipboard-history';
import { processClipboardText } from './src/shared/clipboard-text-processing';
let state = {isEnabled:true,totalBytes:100,entries:[
{id:'11111111-1111-4111-8111-111111111111',text:' hello World ',copiedAt:3},
{id:'22222222-2222-4222-8222-222222222222',text:'{"id":900719925474099312345,"a":[1,2]}',copiedAt:2},
{id:'33333333-3333-4333-8333-333333333333',text:'not json %FF',copiedAt:1}], images:[]};
const listeners=[];
const host={state,copies:[],edits:0,dismissals:0,clear(){state.entries=[];emit();}};
const emit=()=>listeners.forEach(fn=>fn(structuredClone(state)));
function output(request){const entry=state.entries.find(e=>e.id===request.id);if(!entry)throw Error('已删除');if(request.sourceText!==undefined&&request.sourceText!==entry.text)throw Error('原记录已修改');return request.editedText===undefined?processClipboardText(entry.text,request.action):processClipboardText(request.editedText,'original');}
const bridge={
 getClipboardHistory:async()=>structuredClone(state),onClipboardHistoryChanged:fn=>{listeners.push(fn);return()=>{};},
 editClipboardHistoryEntry:async request=>{const entry=state.entries.find(e=>e.id===request.id);if(!entry)throw Error('已删除');if(request.expectedText!==undefined&&request.expectedText!==entry.text)throw Error('原记录已修改');entry.text=processClipboardText(request.text,'original');host.edits++;emit();},
 useClipboardHistoryText:async request=>{host.copies.push(output(request));return{status:'已复制。'};},
 copyClipboardQuickEntry:async(id,action,preview)=>{host.copies.push(output({id,action:action??'original',sourceText:preview?.sourceText,editedText:preview?.text}));host.dismissals++;},
 deleteClipboardHistoryEntry:async id=>{state.entries=state.entries.filter(e=>e.id!==id);emit();},
 setClipboardHistoryEnabled:async enabled=>{state.isEnabled=enabled;emit();},clearClipboardHistory:async()=>{host.clear();},
 dismissClipboardQuick:async()=>{host.dismissals++;}, showClipboardHistory:async()=>{},
};
const mode=new URLSearchParams(location.search).get('mode');
const panel=mode==='quick'?new ClipboardQuickPanel(document.querySelector('main'),bridge):new ClipboardHistoryPanel(document.querySelector('main'),bridge,()=>{});
window.fixture={...host,reopen(){panel.resetForShow();}};
`, resolveDir: process.cwd(), sourcefile: 'clipboard-processing-fixture.ts', loader: 'ts'}, bundle: true, platform: 'browser', format: 'esm', write: false});
const server=createServer((request,response)=>{
    const url=new URL(request.url!,'http://localhost'),pathname=url.pathname;
    if(pathname==='/fixture.js'){response.writeHead(200,{'content-type':'text/javascript'}).end(fixture.outputFiles[0].contents);return;}
    if(pathname==='/fixture.html'){
        const css=url.searchParams.get('mode')==='quick'?'clipboard-quick':'library';
        response.writeHead(200,{'content-type':'text/html'}).end(`<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><link rel="stylesheet" href="/${css}.css"></head><body><main></main><script type="module" src="/fixture.js"></script></body></html>`);return;
    }
    const file=path.join('dist/renderer',path.basename(pathname));
    void readFile(file).then(data=>response.writeHead(200,{'content-type':'text/css'}).end(data),()=>response.writeHead(404).end());
});
await new Promise<void>(resolve=>server.listen(0,'127.0.0.1',resolve));
const address=server.address();if(!address||typeof address==='string')throw Error('No address');
const browser=await chromium.launch({headless:true,channel:'chrome'});
try{
    await mkdir('.cache/clipboard-text-preview',{recursive:true});
    for(const mode of ['quick','full'] as const)for(const theme of ['light','dark'] as const)for(const size of mode==='quick'?[{width:380,height:520},{width:420,height:540}]:[{width:800,height:560},{width:920,height:680}]){
        const page=await browser.newPage({viewport:size,colorScheme:theme});
        page.setDefaultTimeout(5000);const errors:string[]=[];page.on('pageerror',e=>errors.push(e.message));
        await page.goto(`http://127.0.0.1:${address.port}/fixture.html?mode=${mode}`);
        const tools=page.getByRole('combobox',{name:'快捷处理文字',exact:true});await tools.first().waitFor();assert.equal(await tools.count(),3);
        if(mode==='quick') {
            assert.equal(await page.locator('header').evaluate(node=>getComputedStyle(node).getPropertyValue('-webkit-app-region')), 'drag');
            assert.equal(await page.locator('header button').evaluate(node=>getComputedStyle(node).getPropertyValue('-webkit-app-region')), 'no-drag');
        }
        const before=await page.evaluate(()=>structuredClone((window as any).fixture.state.entries));
        await tools.first().selectOption('uppercase');
        await page.getByText('转为大写 · 预览',{exact:true}).waitFor();
        assert.deepEqual(await page.evaluate(()=>(window as any).fixture.copies),[]);
        assert.equal((await page.getByLabel('处理结果预览',{exact:true}).innerText()).trim(),'HELLO WORLD');
        await page.getByRole('button',{name:'编辑结果',exact:true}).click();
        const input=page.getByRole('textbox',{name:'编辑处理结果',exact:true});await input.fill('重新编辑的结果');
        await page.getByRole('button',{name:'复制处理结果',exact:true}).click();
        assert.deepEqual(await page.evaluate(()=>(window as any).fixture.copies),['重新编辑的结果']);
        assert.deepEqual(await page.evaluate(()=>(window as any).fixture.state.entries),before);
        if(mode==='full')await page.getByRole('button',{name:'取消处理',exact:true}).click();
        await tools.nth(1).selectOption('jsonPretty');
        await page.getByText('JSON 格式化 · 预览',{exact:true}).waitFor();
        assert.match(await page.getByLabel('处理结果预览',{exact:true}).innerText(),/900719925474099312345/);
        await page.screenshot({path:`.cache/clipboard-text-preview/${mode}-${theme}-${size.width}-json.png`});
        await page.getByRole('button',{name:'编辑结果',exact:true}).click();
        await page.getByRole('textbox',{name:'编辑处理结果',exact:true}).fill('');
        assert.equal(await page.getByRole('button',{name:'复制处理结果',exact:true}).isDisabled(),true);
        await page.getByRole('textbox',{name:'编辑处理结果',exact:true}).fill('手动调整后的结果');
        await page.getByRole('button',{name:'保存到本条记录',exact:true}).click();
        assert.equal(await page.evaluate(()=>(window as any).fixture.state.entries[1].text),'手动调整后的结果');
        assert.equal(await page.evaluate(()=>(window as any).fixture.state.entries[1].copiedAt),2);
        assert.deepEqual(await page.evaluate(()=>(window as any).fixture.copies),['重新编辑的结果']);
        await tools.nth(2).selectOption('jsonPretty');
        assert.equal(await page.getByText('JSON 格式化 · 预览',{exact:true}).count(),0);
        assert.match(await page.getByRole('status').innerText(),/JSON/);
        await tools.nth(2).selectOption('urlDecode');
        assert.equal(await page.getByText('URL 解码 · 预览',{exact:true}).count(),0);
        assert.match(await page.getByRole('status').innerText(),/URL/);
        if(mode==='quick') {
            await tools.first().selectOption('uppercase');
            await page.getByRole('button',{name:'编辑结果',exact:true}).click();
            await page.getByRole('textbox',{name:'编辑处理结果',exact:true}).fill('下次不能恢复这个草稿');
            await page.evaluate(()=>(window as any).fixture.reopen());
            assert.equal(await page.getByRole('textbox',{name:'编辑处理结果',exact:true}).count(),0);
            assert.equal(await tools.count(),3);
            assert.equal(await page.evaluate(()=>(window as any).fixture.state.entries[0].text),before[0].text);
        }
        await tools.first().selectOption('urlEncode');
        await page.evaluate(()=>(window as any).fixture.clear());
        assert.equal(await page.getByRole('button',{name:'复制处理结果',exact:true}).count(),0);
        assert.equal(await page.getByRole('textbox',{name:'编辑处理结果',exact:true}).count(),0);
        assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
        assert.deepEqual(errors,[]);await page.close();
    }
    console.log('Quick and full history: per-record previews do not write; edited copy preserves records; explicit save preserves timestamps and clipboard; invalid/empty output disabled; clear releases draft; light/dark layouts passed.');
}finally{await browser.close();server.close();}
