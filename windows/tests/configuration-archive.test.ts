import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, readFile, rm, link, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { defaultConfiguration } from '../src/core/configuration';
import { ConfigurationArchiveStore, serializeFileOperations, validateArchive } from '../src/core/configuration-archive';

async function fixture() {
    const directory = await mkdtemp(join(tmpdir(), 'tcube-archive-'));
    const configurationPath = join(directory, 'configuration.json'), libraryPath = join(directory, 'content-library.json');
    await writeFile(configurationPath, JSON.stringify(defaultConfiguration()));
    await writeFile(libraryPath, '{"version":1,"items":[]}');
    return { directory, configurationPath, libraryPath };
}
test('failed second replacement restores exact original bytes and preserves pre-import backup', async () => {
    const f = await fixture();
    try {
        const original = await readFile(f.configurationPath);
        const store = new ConfigurationArchiveStore(f.configurationPath, f.libraryPath, { beforeWrite: async path => { if (path === f.libraryPath) throw new Error('disk failed'); } });
        const archive = await store.currentArchive(); archive.configuration.scale = 1.3;
        await assert.rejects(store.restore(archive), /disk failed/);
        assert.deepEqual(await readFile(f.configurationPath), original);
        assert.equal((await store.backups()).length, 1);
    } finally { await rm(f.directory, { recursive: true, force: true }); }
});
test('corrupt live data blocks restore without modifying either live file', async () => {
    const f = await fixture();
    try {
        const store = new ConfigurationArchiveStore(f.configurationPath, f.libraryPath), archive = await store.currentArchive();
        await writeFile(f.libraryPath, 'damaged');
        await assert.rejects(store.restore(archive));
        assert.equal(await readFile(f.libraryPath, 'utf8'), 'damaged');
    } finally { await rm(f.directory, { recursive: true, force: true }); }
});
test('exports reject hard links, symlinks and case aliases to live files', async () => {
    const f = await fixture();
    try {
        const store = new ConfigurationArchiveStore(f.configurationPath, f.libraryPath);
        const hard = join(f.directory, 'hard.json'), sym = join(f.directory, 'sym.json');
        await link(f.configurationPath, hard); await symlink(f.libraryPath, sym);
        for (const path of [hard, sym, join(f.directory, 'CONFIGURATION.JSON')]) await assert.rejects(store.export(path), /live data/);
    } finally { await rm(f.directory, { recursive: true, force: true }); }
});
test('archives reject unsupported formats and invalid content before disk writes', () => {
    assert.throws(() => validateArchive({ version: 2 }));
    assert.throws(() => validateArchive({ version: 1, createdAt: new Date().toISOString(), configuration: defaultConfiguration(), contentLibrary: { version: 1, items: [{ id: 'bad' }] } }));
});
test('shared file lock serializes overlapping multi-file writer operations', async () => {
    const order: number[] = []; let release!: () => void;
    const first = serializeFileOperations(['/tmp/config.json', '/tmp/library.json'], async () => { order.push(1); await new Promise<void>(resolve => { release = resolve; }); order.push(2); });
    await new Promise(resolve => setTimeout(resolve, 0));
    const second = serializeFileOperations(['/tmp/library.json'], async () => { order.push(3); });
    await new Promise(resolve => setTimeout(resolve, 0)); assert.deepEqual(order, [1]); release();
    await Promise.all([first, second]); assert.deepEqual(order, [1, 2, 3]);
});
