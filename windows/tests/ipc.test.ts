import test from 'node:test';
import assert from 'node:assert/strict';
import { registerIPC, CHANNELS } from '../src/main/ipc';
import { validateLocalTarget } from '../src/main/targets';

test('installed applications are settings-only and selection uses catalog IDs', async () => {
    const handlers = new Map<string, (event: any, payload?: unknown) => Promise<any>>();
    let added: any;
    const item = { id: 'server', name: 'Editor', path: 'C:\\Editor.exe', kind: 'application' };
    const catalog = {
        list: async () => [{ id: 'known', name: 'Editor', detail: item.path }],
        icons: async () => ({}),
        materialize: async (id: string) => { if (id !== 'known') throw Error('列表'); return item; },
    };
    registerIPC({ handle: (name: string, fn: any) => handlers.set(name, fn) },
        { reportError: () => {}, addApplication: async (destination: any, target: any) => { added = { destination, target }; } } as any,
        sender => sender.id === 1 ? 'widget' : 'settings', catalog as any);
    const frame = {}, event = (id: number) => ({ sender: { id, mainFrame: frame }, senderFrame: frame });
    await assert.rejects(handlers.get(CHANNELS.listApplications)!(event(1)), /authorized/);
    await assert.rejects(handlers.get(CHANNELS.listApplications)!(event(2), 'refresh'), /Invalid/);
    await assert.rejects(handlers.get(CHANNELS.applicationIcons)!(event(2), Array(33).fill('known')), /Invalid/);
    await assert.rejects(handlers.get(CHANNELS.addApplication)!(event(2), { face: 'front', slot: 4, applicationId: 'known' }), /Invalid/);
    await assert.rejects(handlers.get(CHANNELS.addApplication)!(event(2), { face: 'front', slot: 0, applicationId: 'C:\\Arbitrary.exe' }), /列表/);
    await handlers.get(CHANNELS.addApplication)!(event(2), { face: 'front', slot: 2, applicationId: 'known' });
    assert.deepEqual(added, { destination: { face: 'front', slot: 2 }, target: item });
});

test('IPC rejects wrong roles, child frames and unknown web contents before calling host', async () => {
    const handlers = new Map<string, (event: any, payload?: unknown) => Promise<unknown>>();
    let called = 0;
    const host = { applyConfiguration: () => { called++; }, launch: () => { called++; }, reportError: () => {} };
    const mainFrame = {};
    registerIPC({ handle: (name: string, fn: any) => handlers.set(name, fn) }, host as any,
        sender => sender.id === 1 ? 'widget' : sender.id === 2 ? 'settings' : null);
    const event = (id: number, frame = mainFrame) => ({ sender: { id, mainFrame }, senderFrame: frame });
    await assert.rejects(handlers.get(CHANNELS.applyConfiguration)!(event(1), {}), /authorized/);
    await assert.rejects(handlers.get(CHANNELS.launch)!(event(2), { face: 'front', slot: 0 }), /authorized/);
    await assert.rejects(handlers.get(CHANNELS.launch)!(event(99), { face: 'front', slot: 0 }), /authorized/);
    await assert.rejects(handlers.get(CHANNELS.applyConfiguration)!(event(2, {}), {}), /authorized/);
    assert.equal(called, 0);
});

test('IPC bounds-checks gesture IDs, faces, slots and path lists', async () => {
    const handlers = new Map<string, (event: any, payload?: unknown) => Promise<unknown>>();
    let calls = 0;
    registerIPC({ handle: (name: string, fn: any) => handlers.set(name, fn) },
        { endPointer: () => { calls++; }, dropTargets: () => { calls++; }, reportError: () => {} } as any,
        sender => sender.id === 1 ? 'widget' : 'settings');
    const frame = {}, event = (id: number) => ({ sender: { id, mainFrame: frame }, senderFrame: frame });
    for (const payload of [{ gestureId: -1, button: 0, hit: null }, { gestureId: 1, button: 1, hit: null },
        { gestureId: 1, button: 0, hit: null, cancelled: 'yes' }, { gestureId: 1, button: 0, hit: { face: 'other', slot: 0 } }, { gestureId: 1, button: 0, hit: { face: 'front', slot: 4 } }]) {
        await assert.rejects(handlers.get(CHANNELS.endPointer)!(event(1), payload), /Invalid/);
    }
    await assert.rejects(handlers.get(CHANNELS.dropTargets)!(event(2), { face: 'front', paths: Array(5).fill('C:\\A.exe') }), /Invalid/);
    assert.equal(calls, 0);
});

test('target validation rejects commands, URLs, remote paths and incorrect filesystem types', async () => {
    const stats: string[] = [];
    const stat = async (value: string) => { stats.push(value); return { isFile: () => true, isDirectory: () => false }; };
    for (const value of ['calc.exe', 'https://example.com', '\\\\server\\share\\app.exe', 'C:\\app.exe --flag', 'C:\\x.cmd', '\\\\?\\C:\\x.exe']) {
        await assert.rejects(validateLocalTarget(value, undefined, stat), /local|executable|folder/i);
    }
    assert.equal(stats.length, 2); // Absolute candidates are statted; neither is an executable extension.
    assert.equal((await validateLocalTarget('C:\\Apps\\Editor.exe', 'application', stat)).kind, 'application');
    await assert.rejects(validateLocalTarget('C:\\Apps\\Editor.exe', 'folder', stat), /folder/);
});
