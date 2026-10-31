import {test} from 'node:test';
import assert from 'node:assert/strict';
import {registerFeatureIPC,FEATURE_ROLES} from '../src/main/feature-ipc';
import {FEATURE_CHANNELS as C} from '../src/shared/feature-channels';
import type {WindowRole} from '../src/main/ipc';
test('content and privileged file/system operations authorize role and main frame before invocation',async()=>{
    const handlers=new Map<string,(event:any,value?:unknown)=>Promise<unknown>>();let role:WindowRole|null='widget',restoring=false,calls=0;
    const operations=Object.fromEntries(Object.keys(FEATURE_ROLES).map(name=>[name,()=>{calls++;return name;}]));
    registerFeatureIPC({handle:(name,operation)=>{handlers.set(name,operation);}},()=>role,operations,()=>restoring,()=>{});
    const frame={},event={sender:{id:1,mainFrame:frame},senderFrame:frame};
    await assert.rejects(handlers.get(C.getLibrary)!(event),/Not authorized/);
    await assert.rejects(handlers.get(C.confirmImportBackup)!(event,'token'),/Not authorized/);
    assert.equal(calls,0);
    role='settings';
    await assert.rejects(handlers.get(C.setLoginEnabled)!({...event,senderFrame:{}},true),/Not authorized/);
    restoring=true;
    await assert.rejects(handlers.get(C.setLoginEnabled)!(event,true),/恢复/);
    assert.equal(calls,0);
    restoring=false;
    assert.equal(await handlers.get(C.getMaintenanceState)!(event),'getMaintenanceState');
    role='library';assert.equal(await handlers.get(C.getLibrary)!(event),'getLibrary');
    await assert.rejects(handlers.get(C.exportBackup)!(event),/Not authorized/);
    await assert.rejects(handlers.get(C.saveSnippet)!(event,'x'.repeat(8*1024*1024+1)),/请求过大/);
    assert.equal(calls,2);
});

test('clipboard history reads and mutations are library-only and reject child frames', async () => {
    const handlers = new Map<string, (event: any, value?: unknown) => Promise<unknown>>();
    let role: WindowRole = 'settings', calls = 0;
    const operations = Object.fromEntries(Object.keys(FEATURE_ROLES).map(name => [name, () => { calls++; }]));
    registerFeatureIPC({ handle: (channel, operation) => handlers.set(channel, operation) }, () => role, operations, () => false, () => {});
    const frame = {}, event = { sender: { id: 1, mainFrame: frame }, senderFrame: frame };
    for (const channel of [C.getClipboardHistory, C.setClipboardHistoryEnabled, C.deleteClipboardHistoryEntry, C.clearClipboardHistory, C.useClipboardHistoryEntry]) {
        assert.ok(handlers.has(channel));
        await assert.rejects(handlers.get(channel)!(event), /authorized/);
        role = 'library'; await assert.rejects(handlers.get(channel)!({ ...event, senderFrame: {} }), /authorized/);
        role = 'settings';
    }
    assert.equal(calls, 0);
});
