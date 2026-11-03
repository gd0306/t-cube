import assert from 'node:assert/strict';
import test from 'node:test';
import { defaultConfiguration, normalizeConfiguration } from '../src/core/configuration';
import { ClipboardHistory } from '../src/core/clipboard-history';
import { ClipboardHistoryRecorder, clipboardHistoryOperations } from '../src/main/clipboard-history';

test('desktop hiding preferences decode independently and default off', () => {
    const config = defaultConfiguration();
    assert.equal(config.edgeCollapseEnabled, false);
    assert.equal(config.hideWhenFullscreen, false);
    assert.equal(normalizeConfiguration({...config, edgeCollapseEnabled: true}).hideWhenFullscreen, false);
});
test('image history owns bounded compressed payloads, promotes duplicates and evicts independently of text', () => {
    const history = new ClipboardHistory();
    history.add('retained text');
    const fixture = (n: number, length = 100) => ({ png: Buffer.alloc(length, n), width: 20, height: 20, thumbnail: 'data:image/png;base64,eA==' });
    for (let n = 0; n < 11; n++) assert.equal(history.addImage(fixture(n)), true);
    assert.equal(history.imageSnapshot().length, 10);
    const oldest = history.imageSnapshot().at(-1)!;
    assert.equal(history.addImage(fixture(1)), true);
    assert.equal(history.imageSnapshot()[0].id, oldest.id);
    assert.equal(history.addImage({...fixture(1), width: 4001, height: 4000}), false);
    assert.equal(history.addImage(fixture(1, 8 * 1024 * 1024 + 1)), false);
    assert.equal(history.snapshot()[0].text, 'retained text');
    history.clear();
    for (let n = 0; n < 5; n++) history.addImage(fixture(n, 8 * 1024 * 1024));
    assert.equal(history.imageSnapshot().length, 4);
    assert.equal(history.totalImageBytes, 32 * 1024 * 1024);
    const owned = history.image(history.imageSnapshot()[0].id)!;
    owned.png[0] = 99;
    assert.equal(history.image(history.imageSnapshot()[0].id)!.png[0], 4);
    history.clear(); assert.equal(history.totalImageBytes, 0);
});
test('merge uses visible history order, cleans copies only and bounds merged UTF-8 bytes', async () => {
    let sequence = 1, source = ' first  \r\n\r\n\r\n';
    const recorder = new ClipboardHistoryRecorder({sequence: () => sequence, read: async () => source}, () => {}, () => () => {});
    recorder.setEnabled(true); sequence++; await recorder.poll();
    source = ' second '; sequence++; await recorder.poll();
    const entries = recorder.state.entries;
    const request = {ids: [entries[1].id, entries[0].id], trimLines: true, collapseBlankLines: true};
    assert.equal(recorder.merge(request), 'second\nfirst\n');
    assert.equal(recorder.state.entries[1].text, ' first  \r\n\r\n\r\n');
    const uses: unknown[] = [];
    const operations = clipboardHistoryOperations(recorder, async request => { uses.push(request); return {status: 'copied'}; });
    await operations.useClipboardHistoryMerge({...request, paste: false});
    assert.deepEqual(uses, [{text: 'second\nfirst\n', paste: false}]);
    assert.throws(() => recorder.merge({...request, ids: [entries[0].id, entries[0].id]}));
    assert.throws(() => operations.useClipboardHistoryEntry({id: entries[0].id, paste: false, image: 'untrusted'}));
    recorder.dispose();
});
test('edge presentation is delayed, restores resting geometry and respects manual hiding and protection', async () => {
    const { DesktopPresentation } = await import('../src/core/desktop-presentation');
    const policy = new DesktopPresentation();
    const base = { frame: {x: 8, y: 100, width: 164, height: 164}, displays: [{x:0,y:0,width:1000,height:800}], cursor: {x:500,y:400}, enabled:true, fullscreen:false, manualVisible:true, protected:false, now:0 };
    assert.equal(policy.update(base).collapsed, false);
    const collapsed = policy.update({...base,now:801});
    assert.equal(collapsed.collapsed, true); assert.equal(collapsed.handle?.x, 0); assert.equal(collapsed.handle?.width, 10);
    assert.equal(policy.update({...base,now:900,cursor:{x:3,y:182}}).collapsed, false);
    policy.update({...base,now:1900,cursor:{x:3,y:182}});
    assert.equal(policy.update({...base,now:2800,cursor:{x:3,y:182}}).collapsed, false, 'Stationary handle pointer must not recollapse');
    assert.equal(policy.update({...base,now:2000,protected:true}).collapsed, false);
    assert.equal(policy.update({...base,now:3000,fullscreen:true}).visible, false);
    assert.equal(policy.update({...base,now:4000,manualVisible:false}).visible, false);
    assert.equal(policy.update({...base,now:5000,frame:{...base.frame,x:300}}).collapsed, false);
    assert.equal(base.frame.x, 8);
});
test('edge collapse ignores adjoining display edges and fullscreen matching is monitor specific', async () => {
    const { edgeHandle, isFullscreenOnDisplay } = await import('../src/core/desktop-presentation');
    const displays = [{x:0,y:0,width:1000,height:800},{x:1000,y:0,width:1000,height:800}];
    assert.equal(edgeHandle({x:830,y:100,width:164,height:164},displays), null);
    assert.equal(isFullscreenOnDisplay({x:0,y:0,width:1000,height:800},displays[0]),true);
    assert.equal(isFullscreenOnDisplay({x:0,y:0,width:1000,height:800},displays[1]),false);
    assert.equal(isFullscreenOnDisplay({x:0,y:0,width:1000,height:760},displays[0]),false);
});
test('image reader checks exclusions before image access and sequence again before decoding', async () => {
    const { readHistoryClipboardContent } = await import('../src/main/history-clipboard-reader');
    let reads = 0, decodes = 0, current = true;
    const normalize = (png: Buffer) => { decodes++; return {png,width:1,height:1,thumbnail:''}; };
    const image = {types:['image/png'],getType:async () => {reads++; return new Blob(['fixture']);}};
    const exclude = {types:['electron application/osclipboard;format="ExcludeClipboardContentFromMonitorProcessing"'],getType:async () => {throw Error('metadata must not read');}};
    assert.equal(await readHistoryClipboardContent([image,exclude],()=>current,normalize),null);
    assert.equal(reads,0);
    const changed = {...image,getType:async () => {current=false;return new Blob(['fixture']);}};
    assert.equal(await readHistoryClipboardContent([changed],()=>current,normalize),null);
    assert.equal(decodes,0);
    current=true;
    assert.deepEqual(await readHistoryClipboardContent([image],()=>current,normalize),{png:Buffer.from('fixture'),width:1,height:1,thumbnail:''});
});
test('PNG header dimensions reject huge allocation and malformed input before native decode', async () => {
    const { pngDimensions } = await import('../src/core/clipboard-image');
    const header = Buffer.alloc(33); Buffer.from('89504e470d0a1a0a','hex').copy(header); header.writeUInt32BE(13,8); header.write('IHDR',12); header.writeUInt32BE(4000,16); header.writeUInt32BE(4000,20);
    assert.deepEqual(pngDimensions(header),{width:4000,height:4000});
    header.writeUInt32BE(4001,16); assert.equal(pngDimensions(header),null);
    assert.equal(pngDimensions(Buffer.alloc(40)),null);
});
test('fullscreen native policy excludes own windows, desktop shell and maximized title bars', async () => {
    const { fullscreenCandidate } = await import('../src/native/fullscreen');
    const fixture = {window:1n,processId:123,visible:true,minimized:false,className:'Chrome_WidgetWin_1',style:0,frame:{x:0,y:0,width:1000,height:800}};
    assert.deepEqual(fullscreenCandidate(fixture,999),fixture.frame);
    for (const patch of [{processId:999},{className:'WorkerW'},{className:'Shell_TrayWnd'},{visible:false},{minimized:true},{style:0x00c00000}]) assert.equal(fullscreenCandidate({...fixture,...patch},999),null);
});
test('image recorder state exposes thumbnails only and image operations resolve authoritative IDs', async () => {
    let sequence=1;
    const owned={png:Buffer.from('owned compressed payload'),width:1,height:1,thumbnail:'data:image/png;base64,eA=='};
    const recorder=new ClipboardHistoryRecorder({sequence:()=>sequence,read:async()=>owned},()=>{},()=>()=>{});
    recorder.setEnabled(true);sequence++;await recorder.poll();
    const state=recorder.state,entry=state.images![0];
    assert.equal('png' in entry,false);assert.equal(JSON.stringify(state).includes('owned compressed payload'),false);
    const used:unknown[]=[];
    const operations=clipboardHistoryOperations(recorder,async()=>{throw Error('image must not use text path');},async(image,paste)=>{used.push({bytes:image.png.toString(),paste});return {status:'copied'};},image=>`${image.width} preview`);
    assert.equal(operations.getClipboardHistoryImage(entry.id),'1 preview');
    await operations.useClipboardHistoryEntry({id:entry.id,paste:true});
    assert.deepEqual(used,[{bytes:'owned compressed payload',paste:true}]);
    assert.throws(()=>operations.useClipboardHistoryEntry({id:entry.id,paste:false,png:'untrusted'}));
    recorder.clear();assert.equal(recorder.state.totalImageBytes,0);assert.throws(()=>operations.getClipboardHistoryImage(entry.id));
    recorder.dispose();
});
test('merged UTF-8 output rejects more than64 KiB and cannot use deleted selection', async () => {
    let sequence=1,source='';
    const recorder=new ClipboardHistoryRecorder({sequence:()=>sequence,read:async()=>source},()=>{},()=>()=>{});
    recorder.setEnabled(true);
    for(let i=0;i<2;i++){source=String(i)+'界'.repeat(21844);sequence++;await recorder.poll();}
    const request={ids:recorder.state.entries.map(entry=>entry.id),trimLines:false,collapseBlankLines:false};
    assert.throws(()=>recorder.merge(request),/64 KiB/);
    recorder.delete(request.ids.pop()!);
    assert.ok(Buffer.byteLength(recorder.merge(request))<=64*1024);
    recorder.delete(request.ids[0]);assert.throws(()=>recorder.merge(request),/已删除/);
    recorder.dispose();
});
test('display topology changes reveal collapsed cubes without mutating old placement', async () => {
    const {DesktopPresentation}=await import('../src/core/desktop-presentation');
    const presentation=new DesktopPresentation();
    const input={frame:{x:8,y:100,width:164,height:164},displays:[{x:0,y:0,width:1000,height:800}],cursor:{x:500,y:400},enabled:true,fullscreen:false,manualVisible:true,protected:false,now:0};
    presentation.update(input);assert.equal(presentation.update({...input,now:900}).collapsed,true);
    assert.equal(presentation.update({...input,displays:[...input.displays,{x:-1000,y:0,width:1000,height:800}],now:1000}).visible,true);
    assert.equal(input.frame.x,8);
});
test('JPEG dimensions and image-only MIME variants are bounded before native normalization', async () => {
    const {imageDimensions}=await import('../src/core/clipboard-image');
    const jpeg=Buffer.from([0xff,0xd8,0xff,0xc0,0,17,8,0x0f,0xa0,0x0f,0xa0,3,1,0x11,0,2,0x11,0,3,0x11,0,0xff,0xd9]);
    assert.deepEqual(imageDimensions(jpeg),{width:4000,height:4000});
    jpeg.writeUInt16BE(4001,9);assert.equal(imageDimensions(jpeg),null);
    const {readHistoryClipboardContent}=await import('../src/main/history-clipboard-reader');
    let normalized=false;
    assert.ok(await readHistoryClipboardContent([{types:['image/jpeg'],getType:async()=>new Blob([jpeg])}],()=>true,()=>{normalized=true;return null;}));
    assert.equal(normalized,true);
});

test('fullscreen selection follows topmost foreign normal window on cube display, ignoring activity elsewhere', async () => {
    const {fullscreenWindowOnDisplay}=await import('../src/native/fullscreen');
    const fixture={window:1n,processId:123,visible:true,minimized:false,className:'Application',style:0,frame:{x:0,y:0,width:1000,height:800}};
    const other={...fixture,window:2n,frame:{x:1000,y:0,width:1000,height:800},style:0x00c00000};
    assert.deepEqual(fullscreenWindowOnDisplay([other,fixture],fixture.frame,999),fixture.frame);
    assert.equal(fullscreenWindowOnDisplay([{...fixture,style:0x00c00000},fixture],fixture.frame,999),null);
    assert.deepEqual(fullscreenWindowOnDisplay([{...fixture,processId:999},fixture],fixture.frame,999),fixture.frame);
});
test('physical display seams stay interior even when an adjoining side taskbar changes usable edges', async () => {
    const {edgeHandle}=await import('../src/core/desktop-presentation');
    const work=[{x:40,y:0,width:960,height:800},{x:-1000,y:0,width:1000,height:800}];
    const physical=[{x:0,y:0,width:1000,height:800},{x:-1000,y:0,width:1000,height:800}];
    assert.equal(edgeHandle({x:48,y:100,width:164,height:164},work,physical),null);
});
test('explicit show overrides fullscreen until fullscreen leaves, then auto hiding resumes', async () => {
    const {DesktopPresentation}=await import('../src/core/desktop-presentation');
    const policy=new DesktopPresentation();
    const input={frame:{x:300,y:100,width:164,height:164},displays:[{x:0,y:0,width:1000,height:800}],cursor:{x:500,y:400},enabled:false,fullscreen:true,manualVisible:true,protected:false,now:0};
    assert.equal(policy.update(input).visible,false);policy.reveal();
    assert.equal(policy.update({...input,now:1000}).visible,true);
    assert.equal(policy.update({...input,fullscreen:false,now:2000}).visible,true);
    assert.equal(policy.update({...input,now:3000}).visible,false);
});

test('fullscreen hiding defers protected desktop interactions', async()=>{
    const {DesktopPresentation}=await import('../src/core/desktop-presentation');
    const policy=new DesktopPresentation();
    assert.equal(policy.update({frame:{x:300,y:100,width:164,height:164},displays:[{x:0,y:0,width:1000,height:800}],cursor:{x:500,y:400},enabled:false,fullscreen:true,manualVisible:true,protected:true,now:0}).visible,true);
});
test('oversized image admission reports a bounded reason without payload materialization', async()=>{
    const {readHistoryClipboardContent}=await import('../src/main/history-clipboard-reader');
    const result=await readHistoryClipboardContent([{types:['image/png'],getType:async()=>new Blob([new Uint8Array(8*1024*1024+1)])}],()=>true,()=>{throw Error('must not decode');});
    assert.ok(result && typeof result==='object' && 'skippedImage' in result);
});
test('native DIB/PNG preflight bounds raw allocation before Electron materializes image blobs', async()=>{
    const {historyImageFormatsAllowed}=await import('../src/native/clipboard-history');
    const dib=Buffer.alloc(40);dib.writeUInt32LE(40);dib.writeInt32LE(4000,4);dib.writeInt32LE(4000,8);
    let size=64*1024*1024;
    const native={register:()=>50000,has:(format:number)=>format===8,readHeader:()=>({size,bytes:dib})};
    assert.equal(historyImageFormatsAllowed(native),true);
    dib.writeInt32LE(4001,4);assert.equal(historyImageFormatsAllowed(native),false);
    dib.writeInt32LE(4000,4);size=70*1024*1024;assert.equal(historyImageFormatsAllowed(native),false);
    assert.equal(historyImageFormatsAllowed({...native,has:format=>format===50000,readHeader:()=>({size:8*1024*1024+1,bytes:Buffer.alloc(40)})}),false);
});
test('private processor data URL replies enforce PNG dimensions without decoding full preview',async()=>{
    const {boundedPNGDataURL}=await import('../src/core/clipboard-image');
    const header=Buffer.alloc(33);Buffer.from('89504e470d0a1a0a','hex').copy(header);header.writeUInt32BE(13,8);header.write('IHDR',12);header.writeUInt32BE(128,16);header.writeUInt32BE(128,20);
    const url=()=>`data:image/png;base64,${header.toString('base64')}`;
    assert.equal(boundedPNGDataURL(url(),128,128*1024),true);
    header.writeUInt32BE(129,16);assert.equal(boundedPNGDataURL(url(),128,128*1024),false);
    header.writeUInt32BE(961,16);assert.equal(boundedPNGDataURL(url(),960,6*1024*1024),false);
    assert.equal(boundedPNGDataURL('data:image/png;base64,eA==',128,128*1024),false);
});
