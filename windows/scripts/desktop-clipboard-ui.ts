/** Headless Chrome checks the actual production history panel using owned, in-memory fixtures. */
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {chromium} from 'playwright';
import {readFile, mkdir} from 'node:fs/promises';
import {mergeHistoryText} from '../src/shared/clipboard-history';
const bundled = await build({stdin:{contents:"export {ClipboardHistoryPanel} from './src/renderer/clipboard-history';",resolveDir:process.cwd()},bundle:true,write:false,format:'iife',globalName:'TCubeHistory',platform:'browser'});
const browser = await chromium.launch({headless:true,executablePath:process.env.TCUBE_CHROME_EXECUTABLE ?? (process.platform==='darwin'?'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome':undefined)});
const page = await browser.newPage({viewport:{width:940,height:700}});
const uses: unknown[] = [], drafts: string[] = [];
await page.exposeFunction('ownedUse',(request:unknown)=>{uses.push(request);return {status:'Owned fixture copied'};});
await page.exposeFunction('ownedMerge',(request:{ids:string[];trimLines:boolean;collapseBlankLines:boolean;paste?:boolean})=>{
    const texts = [' second changed ',' first  \r\n\r\n\r\n'];
    const value = mergeHistoryText(['newer','older'].filter(id=>request.ids.includes(id)).map(id=>texts[id==='newer'?0:1]),request);
    if(request.paste!==undefined)uses.push({text:value,paste:request.paste});
    return request.paste===undefined?value:{status:'Owned merge copied'};
});
await page.exposeFunction('ownedDraft',(text:string)=>{drafts.push(text);});
try {
    await page.setContent('<!doctype html><meta charset="utf-8"><main id="root"></main>');
    await page.addScriptTag({content:'window.__name = (value) => value;'});
    await page.addStyleTag({content:await readFile('src/renderer/library.css','utf8')});
    await page.addScriptTag({content:bundled.outputFiles[0].text});
    await page.evaluate(()=>{
        const fixture={isEnabled:false,totalBytes:30,entries:[{id:'newer',text:' second ',copiedAt:2},{id:'older',text:' first  \r\n\r\n\r\n',copiedAt:1}],images:[{id:'image',width:1,height:1,copiedAt:3,thumbnail:'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=='}]};
        let changed:(state:unknown)=>void=()=>{};
        const globals=window as any;
        globals.ownedState=fixture;
        globals.historyPanel=new globals.TCubeHistory.ClipboardHistoryPanel(document.querySelector('#root'),{
            getClipboardHistory:async()=>fixture,onClipboardHistoryChanged:(callback:any)=>{changed=callback;return()=>{};},
            editClipboardHistoryEntry:async(request:{id:string;text:string})=>{const entry=fixture.entries.find(entry=>entry.id===request.id);if(!entry)throw Error('missing');entry.text=request.text;changed(fixture);},
            setClipboardHistoryEnabled:async(enabled:boolean)=>{fixture.isEnabled=enabled;changed(fixture);},
            getClipboardHistoryImage:async()=>fixture.images[0].thumbnail,
            useClipboardHistoryEntry:globals.ownedUse,useClipboardHistoryMerge:globals.ownedMerge,previewClipboardHistoryMerge:globals.ownedMerge,
            deleteClipboardHistoryEntry:async(id:string)=>{fixture.images=fixture.images.filter(entry=>entry.id!==id);changed(fixture);},
            clearClipboardHistory:async()=>{fixture.entries=[];fixture.images=[];changed(fixture);},
        },globals.ownedDraft);
    });
    await page.getByRole('button',{name:'启用记录',exact:true}).click();
    assert.equal(await page.getByRole('button',{name:'暂停记录',exact:true}).count(),1);
    await page.getByRole('button',{name:'编辑历史文字',exact:true}).click();
    await page.getByRole('textbox',{name:'编辑历史文字',exact:true}).fill('cancelled');
    await page.getByRole('button',{name:'取消编辑',exact:true}).click();
    assert.equal(await page.locator('.history-detail pre').textContent(),' second ');
    await page.getByRole('button',{name:'编辑历史文字',exact:true}).click();
    await page.getByRole('textbox',{name:'编辑历史文字',exact:true}).fill(' second changed ');
    await page.getByRole('button',{name:'保存历史文字',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector('.history-detail pre')?.textContent===' second changed ');
    assert.equal(uses.length,0);
    await page.getByRole('checkbox',{name:'选择文字 2',exact:true}).check();
    await page.getByRole('checkbox',{name:'选择文字 1',exact:true}).check();
    await page.getByRole('checkbox',{name:'去除每行首尾空白',exact:true}).check();
    await page.getByRole('checkbox',{name:'合并连续空行',exact:true}).check();
    assert.equal(await page.locator('.history-detail pre').textContent(),'second changed\nfirst\n');
    await page.getByRole('button',{name:'复制合并文字',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector('[role=status]')?.textContent==='Owned merge copied');
    assert.deepEqual(uses,[{text:'second changed\nfirst\n',paste:false}]);
    await page.getByRole('button',{name:'整理为常用内容',exact:true}).click();
    await page.waitForTimeout(50); assert.deepEqual(drafts,['second changed\nfirst\n']);
    await page.getByRole('searchbox',{name:'搜索剪贴板历史',exact:true}).fill('second');
    assert.equal(await page.getByRole('button',{name:'复制合并文字',exact:true}).count(),0,'Filtering must clear stale merge selection');
    await page.getByRole('button',{name:'图片',exact:true}).click();
    await page.getByAltText('所选历史图片预览').waitFor();
    assert.equal(await page.getByRole('button',{name:'整理为常用内容',exact:true}).count(),0,'Images do not convert to snippets');
    await page.getByRole('button',{name:'复制历史图片',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector('[role=status]')?.textContent==='Owned fixture copied');
    assert.deepEqual(uses.at(-1),{id:'image',paste:false});
    await mkdir('.cache/smoke',{recursive:true});
    await page.screenshot({path:'.cache/smoke/desktop-clipboard-images.png'});
    await page.getByRole('button',{name:'删除历史',exact:true}).click();
    assert.equal(await page.locator('.history-image-preview').count(),0);
    await page.getByRole('button',{name:'文字',exact:true}).click();
    await page.getByRole('checkbox',{name:'选择文字 1',exact:true}).check();
    await page.getByRole('checkbox',{name:'选择文字 2',exact:true}).check();
    await page.screenshot({path:'.cache/smoke/desktop-clipboard-merge.png'});
    await page.evaluate(()=>{(window as any).historyPanel.dispose();});
    console.log('Production history UI: deterministic merge/cleanup, authoritative use/draft, filter reset, image category/preview/copy/delete passed.');
} finally {await browser.close();}
