import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdir, mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { build } from 'esbuild';
import { runDisplayInputProcess } from '../src/main/display-input-process';
const fixture = path.resolve('tests/fixtures/display-input-process.cjs');
const electron = createRequire(import.meta.url)('electron') as string;
test('real Electron-as-Node child completes read and honours cancellation', async () => {
    assert.equal((await runDisplayInputProcess(fixture, { kind: 'list' }, 5000, electron).result).status, 'listed');
    const directory = await mkdtemp(path.join(tmpdir(), 'tcube-process-')); const pidFile = path.join(directory, 'pid');
    try {
        const operation = runDisplayInputProcess(fixture, { kind: 'switch', identity: pidFile, target: 'hdmi' }, 5000, electron);
        for (let i = 0; i < 100; i++) { try { await readFile(pidFile); break; } catch { await new Promise(resolve => setTimeout(resolve, 20)); } }
        operation.cancel(); assert.equal((await operation.result).status, 'no-op');
    } finally { await rm(directory, { recursive: true, force: true }); }
});
test('stalled process is terminated at the deadline and switch is unconfirmed', async () => {
    const directory = await mkdtemp(path.join(tmpdir(), 'tcube-stall-')); const pidFile = path.join(directory, 'pid');
    try {
        const operation = runDisplayInputProcess(fixture, { kind: 'switch', identity: pidFile, target: 'typeC', mapping: { typeC: 7, hdmi: 5 } }, 1200, electron);
        const result = await operation.result; assert.equal(result.status, 'sent-unconfirmed');
        const pid = Number(await readFile(pidFile, 'utf8')); assert.throws(() => process.kill(pid, 0));
    } finally { await rm(directory, { recursive: true, force: true }); }
});

test('stalled preflight is an error, never reported as a sent switch', async () => {
    const directory = await mkdtemp(path.join(tmpdir(), 'tcube-preflight-')); const pidFile = path.join(directory, 'pid');
    try {
        const operation = runDisplayInputProcess(fixture, { kind: 'switch', identity: pidFile, target: 'typeC' }, 1200, electron);
        await assert.rejects(operation.result, /超时/);
        const pid = Number(await readFile(pidFile, 'utf8')); assert.throws(() => process.kill(pid, 0));
    } finally { await rm(directory, { recursive: true, force: true }); }
});

test('abnormal child exit distinguishes preflight from a write that may have started', async () => {
    const base = { kind: 'switch' as const, identity: '', target: 'typeC' as const };
    await assert.rejects(runDisplayInputProcess(fixture, { ...base, mapping: { typeC: 9, hdmi: 5 } }, 5000, electron).result, /进程退出/);
    const result = await runDisplayInputProcess(fixture, { ...base, mapping: { typeC: 8, hdmi: 5 } }, 5000, electron).result;
    assert.equal(result.status, 'sent-unconfirmed');
});
test('normal child reports distinguish rejected writes and pre-Set cancellation from uncertainty', async () => {
    const base = { kind: 'switch' as const, identity: '', target: 'typeC' as const };
    await assert.rejects(runDisplayInputProcess(fixture, { ...base, mapping: { typeC: 10, hdmi: 5 } }, 5000, electron).result, /rejected/);
    await assert.rejects(runDisplayInputProcess(fixture, { ...base, mapping: { typeC: 11, hdmi: 5 } }, 5000, electron).result, /cancelled/);
    assert.equal((await runDisplayInputProcess(fixture, { ...base, mapping: { typeC: 12, hdmi: 5 } }, 5000, electron).result).status, 'sent-unconfirmed');
});

test('real job classifications survive the Electron child boundary', async () => {
    const cache = path.resolve('.cache'); await mkdir(cache, { recursive: true }); const dir = await mkdtemp(path.join(cache, 'classification-'));
    try {
        const worker = path.join(dir, 'worker.cjs');
        await build({ entryPoints: ['tests/fixtures/display-input-classification.ts'], outfile: worker, bundle: true, platform: 'node', target: 'node22', format: 'cjs' });
        const base = { kind: 'switch' as const, identity: '\\\\?\\DISPLAY#IOCFFFF#instance#{e6f07b5f-ee97-4a90-b076-33f57bf4eaa7}', target: 'typeC' as const };
        await assert.rejects(runDisplayInputProcess(worker, { ...base, mapping: { typeC: 10, hdmi: 5 } }, 5000, electron).result, /writes=1/);
        await assert.rejects(runDisplayInputProcess(worker, { ...base, mapping: { typeC: 11, hdmi: 5 } }, 5000, electron).result, /writes=0/);
        assert.equal((await runDisplayInputProcess(worker, { ...base, mapping: { typeC: 12, hdmi: 5 } }, 5000, electron).result).status, 'sent-unconfirmed');
    } finally { await rm(dir, { recursive: true, force: true }); }
});
