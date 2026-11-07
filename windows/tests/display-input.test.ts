import test from 'node:test';
import assert from 'node:assert/strict';
import { runDisplayInputJob, type DisplayInputDriver } from '../src/native/display-input';
import { DisplayInputStore } from '../src/main/display-input-store';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
const id = '\\\\?\\DISPLAY#IOCFFFF#instance#{e6f07b5f-ee97-4a90-b076-33f57bf4eaa7}';
test('fresh target preflight writes once and lost readback is unconfirmed; handles are closed', async () => {
    const calls: string[] = []; let reads = 0;
    const driver: DisplayInputDriver<number> = {
        enumerate: () => [{ identity: id, name: 'monitor', handles: [1] }],
        read: () => { calls.push('read'); return reads++ ? null : { current: 5, maximum: 14 }; },
        write: (_handle, value) => { calls.push(`write:${value}`); return true; },
        destroy: () => { calls.push('destroy'); }, delay: () => {}
    };
    const result = await runDisplayInputJob(driver, { kind: 'switch', identity: id.toUpperCase(), mapping: { typeC: 7, hdmi: 5 }, target: 'typeC' });
    assert.equal(result.status, 'sent-unconfirmed');
    assert.deepEqual(calls, ['read', 'write:7', 'read', 'destroy']);
});
test('ambiguous targets never write, and all handles are closed', async () => {
    let writes = 0; let destroyed = 0;
    const driver: DisplayInputDriver<number> = { enumerate: () => [{ identity: id, name: '', handles: [1, 2] }], read: () => ({ current: 16, maximum: 3 }), write: () => { writes++; return true; }, destroy: () => { destroyed++; }, delay: () => {} };
    await assert.rejects(runDisplayInputJob(driver, { kind: 'switch', identity: id, mapping: { typeC: 7, hdmi: 5 }, target: 'typeC' }));
    assert.equal(writes, 0); assert.equal(destroyed, 2);
});
test('mapping store validates and preserves corrupt bytes', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'tcube-input-')); const file = join(dir, 'display-inputs.json');
    try {
        const store = new DisplayInputStore(file);
        await store.save(id, { typeC: 7, hdmi: 5 });
        assert.deepEqual((await store.load()).mappings[id.toLowerCase()], { typeC: 7, hdmi: 5 });
        await assert.rejects(store.save(id, { typeC: 5, hdmi: 5 }));
        await writeFile(file, '{broken');
        await assert.rejects(store.save(id, { typeC: 7, hdmi: 5 }));
        assert.equal(await readFile(file, 'utf8'), '{broken');
    } finally { await rm(dir, { recursive: true, force: true }); }
});
test('unrecognized source, cancellation, and same source do not send a command', async () => {
    let writes = 0, reads = 0, current = 16;
    const driver: DisplayInputDriver<number> = { enumerate: () => [{ identity: id, name: '', handles: [1] }], read: () => { reads++; return { current, maximum: 3 }; }, write: () => { writes++; return true; }, destroy: () => {}, delay: () => {} };
    const job = { kind: 'switch' as const, identity: id, mapping: { typeC: 7, hdmi: 5 }, target: 'typeC' as const };
    await assert.rejects(runDisplayInputJob(driver, job), /not calibrated/);
    current = 5;
    await assert.rejects(runDisplayInputJob(driver, job, () => true), /cancelled/);
    current = 7;
    assert.equal((await runDisplayInputJob(driver, job)).status, 'no-op');
    assert.equal(writes, 0); assert.equal(reads, 3);
});
test('readback exception after acceptance remains unconfirmed', async () => {
    let reads = 0, writes = 0;
    const driver: DisplayInputDriver<number> = { enumerate: () => [{ identity: id, name: '', handles: [1] }], read: () => { if (reads++) throw new Error('read lost'); return { current: 5, maximum: 14 }; }, write: () => { writes++; return true; }, destroy: () => {}, delay: () => {} };
    const result = await runDisplayInputJob(driver, { kind: 'switch', identity: id, mapping: { typeC: 7, hdmi: 5 }, target: 'typeC' });
    assert.equal(result.status, 'sent-unconfirmed'); assert.equal(writes, 1);
});
test('panel IPC authorizes before payload inspection or service calls', async () => {
    const { handleDisplayInputRequest } = await import('../src/main/display-input-ipc');
    let calls = 0; const service = { list: async () => { calls++; }, save: async () => { calls++; }, switch: async () => { calls++; }, close: () => { calls++; } };
    const hostile = new Proxy({}, { get() { throw new Error('payload accessed'); } });
    await assert.rejects(handleDisplayInputRequest('switch', false, hostile, service), /Unauthorized/);
    await assert.rejects(handleDisplayInputRequest('switch', true, { identity: id, target: 'arbitrary' }, service), /Invalid/);
    await assert.rejects(handleDisplayInputRequest('list', true, { extra: true }, service), /Invalid/);
    assert.equal(calls, 0);
    await handleDisplayInputRequest('switch', true, { identity: id, target: 'typeC' }, service); assert.equal(calls, 1);
});
test('monitor model never supplies guessed input codes without saved calibration', async () => {
    let writes = 0;
    const driver: DisplayInputDriver<number> = { enumerate: () => [{ identity: id, name: '27C1U-D', handles: [1], knownModel: true }], read: () => ({ current: 5, maximum: 14 }), write: () => { writes++; return true; }, destroy: () => {}, delay: () => {} };
    await assert.rejects(runDisplayInputJob(driver, { kind: 'switch', identity: id, target: 'typeC' }), /Configure/);
    assert.equal(writes, 0);
});
test('listing keeps unsupported and ambiguous monitors visible and isolates read failures', async () => {
    const closed: number[] = [];
    const driver: DisplayInputDriver<number> = {
        enumerate: () => [
            { identity: id, name: 'Generic A', handles: [1] },
            { identity: id.replace('instance', 'other'), name: 'No DDC', handles: [2] },
            { identity: '', name: 'No transport', handles: [] },
            { identity: id.replace('instance', 'clone'), name: 'Clone A', handles: [3] },
            { identity: id.replace('instance', 'clone').toUpperCase(), name: 'Clone B', handles: [4] }
        ],
        read: handle => { if (handle === 2) throw new Error('DDC unsupported'); assert.equal(handle, 1); return { current: 17, maximum: 3 }; },
        write: () => { throw new Error('listing must not switch'); }, destroy: handle => { closed.push(handle); }, delay: () => {}
    };
    const result = await runDisplayInputJob(driver, { kind: 'list' });
    assert.equal(result.status, 'listed');
    if (result.status === 'listed') {
        assert.equal(result.displays.length, 5);
        assert.equal(result.displays[0].reading?.current, 17);
        assert.ok(result.displays.slice(1).every(display => display.reading === null));
    }
    assert.deepEqual(closed, [1, 2, 3, 4]);
});
test('service rejects duplicate switch, cancels a running worker and skips queued work', async () => {
    const { DisplayInputService } = await import('../src/main/display-input-service');
    const dir = await mkdtemp(join(tmpdir(), 'tcube-input-queue-')); const file = join(dir, 'display-inputs.json');
    try {
        const store = new DisplayInputStore(file); await store.save(id, { typeC: 7, hdmi: 5 });
        let start!: () => void, release!: () => void, cancelled = 0, calls = 0;
        const started = new Promise<void>(resolve => { start = resolve; });
        const gate = new Promise<void>(resolve => { release = resolve; });
        const service = new DisplayInputService('', store, async (_job, token) => { calls++; start(); await gate; cancelled = Atomics.load(token, 0); return { status: 'no-op', reading: { current: 5, maximum: 14 } }; });
        const first = service.switch(id, 'typeC'); await started;
        await assert.rejects(service.switch(id, 'typeC'), /already in progress/);
        const queued = service.list(); service.cancel(); release(); await assert.rejects(first, /may have been sent/);
        await assert.rejects(queued, /cancelled/); assert.equal(cancelled, 1); assert.equal(calls, 1);
    } finally { await rm(dir, { recursive: true, force: true }); }
});
test('all handles are destroyed when a read or write throws, even if cleanup fails', async () => {
    const destroyed: number[] = [];
    const driver: DisplayInputDriver<number> = { enumerate: () => [{ identity: id, name: '', handles: [1] }, { identity: id.replace('instance', 'other'), name: '', handles: [2] }], read: () => { throw new Error('read failed'); }, write: () => true, destroy: h => { destroyed.push(h); if (h === 1) throw new Error('cleanup failed'); }, delay: () => {} };
    await assert.rejects(runDisplayInputJob(driver, { kind: 'switch', identity: id, mapping: { typeC: 7, hdmi: 5 }, target: 'typeC' }));
    assert.deepEqual(destroyed, [1, 2]);
});
test('IPC accepts only the live panel web contents and its main frame', async () => {
    const { isPanelSender } = await import('../src/main/display-input-ipc');
    const mainFrame = {}; const contents = { mainFrame }; let destroyed = false;
    const panel = { isDestroyed: () => destroyed, webContents: contents };
    assert.equal(isPanelSender(panel, contents, mainFrame), true);
    assert.equal(isPanelSender(panel, {}, mainFrame), false);
    assert.equal(isPanelSender(panel, contents, {}), false);
    destroyed = true; assert.equal(isPanelSender(panel, contents, mainFrame), false);
    assert.equal(isPanelSender(null, contents, mainFrame), false);
});
test('duplicate interface identities are rejected and no write reaches either handle', async () => {
    let writes = 0; const closed: number[] = [];
    const driver: DisplayInputDriver<number> = { enumerate: () => [{ identity: id, name: '', handles: [1] }, { identity: id.toUpperCase(), name: '', handles: [2] }], read: () => ({ current: 5, maximum: 14 }), write: () => { writes++; return true; }, destroy: h => { closed.push(h); }, delay: () => {} };
    await assert.rejects(runDisplayInputJob(driver, { kind: 'switch', identity: id, mapping: { typeC: 7, hdmi: 5 }, target: 'typeC' }), /ambiguous/);
    assert.equal(writes, 0); assert.deepEqual(closed, [1, 2]);
});
test('a matching readback confirms; an unchanged response reports not applied', async () => {
    let after = 7, reads = 0;
    const driver: DisplayInputDriver<number> = { enumerate: () => [{ identity: id, name: '', handles: [1] }], read: () => ({ current: reads++ % 2 ? after : 5, maximum: 14 }), write: () => true, destroy: () => {}, delay: () => {} };
    const job = { kind: 'switch' as const, identity: id, mapping: { typeC: 7, hdmi: 5 }, target: 'typeC' as const };
    assert.equal((await runDisplayInputJob(driver, job)).status, 'confirmed'); after = 5;
    assert.equal((await runDisplayInputJob(driver, job)).status, 'not-applied');
});
test('third valid readback remains unconfirmed and sends only one command', async () => {
    let reads = 0, writes = 0;
    const driver: DisplayInputDriver<number> = { enumerate: () => [{ identity: id, name: '', handles: [1] }], read: () => ({ current: reads++ ? 16 : 5, maximum: 14 }), write: () => { writes++; return true; }, destroy: () => {}, delay: () => {} };
    const result = await runDisplayInputJob(driver, { kind: 'switch', identity: id, mapping: { typeC: 7, hdmi: 5 }, target: 'typeC' });
    assert.equal(result.status, 'sent-unconfirmed'); assert.equal(writes, 1);
});
test('calibration cancelled at atomic commit leaves original file and removes temporary file', async () => {
    const { atomicWriteJSON } = await import('../src/core/atomic-json');
    const { readdir } = await import('node:fs/promises');
    const dir = await mkdtemp(join(tmpdir(), 'tcube-commit-')); const file = join(dir, 'display-inputs.json'); let cancelled = false;
    try {
        const existing = new DisplayInputStore(file); await existing.save(id, { typeC: 7, hdmi: 5 }); const before = await readFile(file, 'utf8');
        const store = new DisplayInputStore(file, (file, data, guard) => atomicWriteJSON(file, data, () => { cancelled = true; guard?.(); }));
        await assert.rejects(store.save(id, { typeC: 1, hdmi: 2 }, () => cancelled), /cancelled/);
        assert.equal(await readFile(file, 'utf8'), before); assert.deepEqual(await readdir(dir), ['display-inputs.json']);
    } finally { await rm(dir, { recursive: true, force: true }); }
});
test('saving and switching serialize so switch uses completed mapping', async () => {
    const { DisplayInputService } = await import('../src/main/display-input-service'); const { atomicWriteJSON } = await import('../src/core/atomic-json');
    const dir = await mkdtemp(join(tmpdir(), 'tcube-order-')); const file = join(dir, 'display-inputs.json');
    try {
        let release!: () => void, start!: () => void; const gate = new Promise<void>(resolve => { release = resolve; }); const started = new Promise<void>(resolve => { start = resolve; });
        const store = new DisplayInputStore(file, async (file, data, guard) => { start(); await gate; await atomicWriteJSON(file, data, guard); });
        let used: unknown; const service = new DisplayInputService('', store, async job => {
            if (job.kind === 'list') return { status: 'listed', displays: [{ identity: id.toLowerCase(), name: 'Generic', reading: { current: 5, maximum: 14 } }] };
            used = job.mapping; return { status: 'no-op', reading: { current: 5, maximum: 14 } };
        });
        const save = service.save(id, { typeC: 7, hdmi: 5 }); await started; const change = service.switch(id, 'typeC'); release(); await save; await change;
        assert.deepEqual(used, { typeC: 7, hdmi: 5 });
    } finally { await rm(dir, { recursive: true, force: true }); }
});
test('service refuses stale or ambiguous calibration saves and preserves existing bytes', async () => {
    const { DisplayInputService } = await import('../src/main/display-input-service');
    const dir = await mkdtemp(join(tmpdir(), 'tcube-stale-input-')); const file = join(dir, 'display-inputs.json');
    try {
        const store = new DisplayInputStore(file); await store.save(id, { typeC: 7, hdmi: 5 });
        const before = await readFile(file, 'utf8');
        for (const displays of [[], [{ identity: id.toLowerCase(), name: 'Clone', reading: null, unavailable: 'identity' as const }]]) {
            const service = new DisplayInputService('', store, async () => ({ status: 'listed', displays }));
            await assert.rejects(service.save(id, { typeC: 15, hdmi: 17 }), /ambiguous|unavailable/);
            assert.equal(await readFile(file, 'utf8'), before);
        }
    } finally { await rm(dir, { recursive: true, force: true }); }
});
test('write-start marker precedes Set, and a marker failure prevents the write', async () => {
    const calls: string[] = [];
    const driver: DisplayInputDriver<number> = { enumerate: () => [{ identity: id, name: '', handles: [1] }], read: () => ({ current: 5, maximum: 14 }), write: () => { calls.push('write'); return true; }, destroy: () => { calls.push('destroy'); }, delay: () => {} };
    const job = { kind: 'switch' as const, identity: id, mapping: { typeC: 7, hdmi: 5 }, target: 'typeC' as const };
    await runDisplayInputJob(driver, job, () => false, () => { calls.push('marker'); });
    assert.deepEqual(calls, ['marker', 'write', 'destroy']); calls.length = 0;
    await assert.rejects(runDisplayInputJob(driver, job, () => false, () => { throw new Error('marker failed'); }), /marker failed/);
    assert.deepEqual(calls, ['destroy']);
});
test('write false is rejected, cancellation after marker is not attempted, and thrown write is uncertain', async () => {
    const { classifyInputError } = await import('../src/native/display-input');
    let writes = 0, marked = 0, checks = 0;
    const driver: DisplayInputDriver<number> = { enumerate: () => [{ identity: id, name: '', handles: [1] }], read: () => ({ current: 5, maximum: 14 }), write: () => { writes++; return false; }, destroy: () => {}, delay: () => {} };
    const job = { kind: 'switch' as const, identity: id, mapping: { typeC: 7, hdmi: 5 }, target: 'typeC' as const };
    await assert.rejects(runDisplayInputJob(driver, job, () => false, () => { marked++; }), error => classifyInputError(error).kind === 'write-rejected');
    assert.equal(writes, 1); assert.equal(marked, 1);
    writes = 0; marked = 0;
    await assert.rejects(runDisplayInputJob(driver, job, () => ++checks === 2, () => { marked++; }), error => classifyInputError(error).kind === 'not-attempted');
    assert.equal(writes, 0); assert.equal(marked, 1);
    driver.write = () => { writes++; throw new Error('native call error'); };
    await assert.rejects(runDisplayInputJob(driver, job), error => classifyInputError(error).kind === 'uncertain');
    assert.equal(writes, 1);
});

test('undefined noncontinuous VCP maximum cannot reject a valid current input', async () => {
    const driver: DisplayInputDriver<number> = {
        enumerate: () => [{ identity: id, name: 'Generic', handles: [1] }],
        read: () => ({ current: 16, maximum: 0xffffffff }),
        write: () => { throw new Error('active input must not be written'); }, destroy: () => {}, delay: () => {}
    };
    const listing = await runDisplayInputJob(driver, { kind: 'list' });
    assert.equal(listing.status, 'listed');
    if (listing.status === 'listed') assert.equal(listing.displays[0].reading?.current, 16);
    assert.equal((await runDisplayInputJob(driver, { kind: 'switch', identity: id, mapping: { typeC: 16, hdmi: 17 }, target: 'typeC' })).status, 'no-op');
});
