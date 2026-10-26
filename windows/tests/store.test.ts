import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ConfigurationStore } from '../src/core/store';

test('serialized atomic updates retain independent concurrent edits and isolate snapshots', async () => {
    const directory = await mkdtemp(join(tmpdir(), 'tcube-store-'));
    try {
        const path = join(directory, 'nested', 'configuration.json');
        const store = new ConfigurationStore(path);
        await store.load();
        await Promise.all([store.update(c => { c.scale = 1.2; }), store.update(c => { c.groups.front.name = 'Tools'; })]);
        const snapshot = store.snapshot; snapshot.scale = 0.7;
        const persisted = JSON.parse(await readFile(path, 'utf8'));
        assert.equal(persisted.scale, 1.2);
        assert.equal(persisted.groups.front.name, 'Tools');
        assert.equal(store.snapshot.scale, 1.2);
        await assert.rejects(store.update(c => { c.scale = 10; }));
        await store.update(c => { c.scale = 1.3; });
        assert.equal(store.snapshot.scale, 1.3);
        assert.deepEqual(await readdir(join(directory, 'nested')), ['configuration.json']);
    } finally { await rm(directory, { recursive: true, force: true }); }
});

test('corrupt load blocks all writes until explicit backup and reset', async () => {
    const directory = await mkdtemp(join(tmpdir(), 'tcube-corrupt-'));
    try {
        const path = join(directory, 'configuration.json');
        const corrupt = '{ user data that cannot decode';
        await writeFile(path, corrupt);
        const store = new ConfigurationStore(path);
        await assert.rejects(store.load());
        await assert.rejects(store.update(c => { c.scale = 1.2; }));
        assert.equal(await readFile(path, 'utf8'), corrupt);
        await store.backupAndReset();
        const backup = (await readdir(directory)).find(name => name.includes('.backup'))!;
        assert.ok(backup);
        assert.equal(await readFile(join(directory, backup), 'utf8'), corrupt);
        assert.equal(store.snapshot.scale, 1);
        assert.equal(JSON.parse(await readFile(path, 'utf8')).scale, 1);
    } finally { await rm(directory, { recursive: true, force: true }); }
});

test('external corruption after a successful load also blocks saving', async () => {
    const directory = await mkdtemp(join(tmpdir(), 'tcube-external-'));
    try {
        const path = join(directory, 'configuration.json');
        const store = new ConfigurationStore(path); await store.load();
        await writeFile(path, 'broken externally');
        await assert.rejects(store.update(c => { c.scale = 1.2; }));
        assert.equal(await readFile(path, 'utf8'), 'broken externally');
    } finally { await rm(directory, { recursive: true, force: true }); }
});
