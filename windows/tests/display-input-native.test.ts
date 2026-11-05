import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdir, mkdtemp, rm } from 'node:fs/promises';
import path from 'node:path';
import { build } from 'esbuild';
import { runDisplayInputProcess } from '../src/main/display-input-process';
test('native Windows enumeration runs read-only in Electron-as-Node process', { skip: process.platform !== 'win32', timeout: 60000 }, async () => {
    const cache = path.resolve('.cache'); await mkdir(cache, { recursive: true }); const directory = await mkdtemp(path.join(cache, 'native-input-'));
    try {
        const worker = path.join(directory, 'worker.cjs');
        await build({ entryPoints: ['src/native/display-input-worker.ts'], outfile: worker, bundle: true, platform: 'node', target: 'node22', format: 'cjs', external: ['koffi'] });
        const electron = createRequire(import.meta.url)('electron') as string;
        const result = await runDisplayInputProcess(worker, { kind: 'list' }, 30000, electron).result;
        assert.equal(result.status, 'listed');
    } finally { await rm(directory, { recursive: true, force: true }); }
});

// The installer check supplies its own executable; this never starts the desktop
// application or sends Set, and resolves the worker/dependencies from the install.
test('installed Windows display worker runs read-only from installed resources', {
    skip: process.platform !== 'win32' || !process.env.TCUBE_SMOKE_EXECUTABLE,
    timeout: 60000
}, async () => {
    const executable = process.env.TCUBE_SMOKE_EXECUTABLE!;
    const worker = path.join(path.dirname(executable), 'resources', 'app', 'dist', 'display-input-worker.cjs');
    const result = await runDisplayInputProcess(worker, { kind: 'list' }, 30000, executable).result;
    assert.equal(result.status, 'listed');
});
