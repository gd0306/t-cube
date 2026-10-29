import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, rm, readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DisplayPositionStore } from '../src/main/display-position-store';
test('independent display store round trips atomic serialized writes and preserves corrupt data', async () => {
    const directory = await mkdtemp(join(tmpdir(), 'tcube-displays-'));
    const filePath = join(directory, 'display-positions.json');
    try {
        const store = new DisplayPositionStore(filePath);
        assert.deepEqual(await store.load(), { version: 1, activeDisplayId: null, positions: {} });
        const memory = { version: 1 as const, activeDisplayId: 'left', positions: { left: { x: 0.5, y: 0.2 } } };
        await Promise.all([store.save(memory), store.save({ ...memory, activeDisplayId: 'primary' })]);
        assert.equal((await new DisplayPositionStore(filePath).load()).activeDisplayId, 'primary');
        assert.deepEqual(await readdir(directory), ['display-positions.json']);
        await writeFile(filePath, '{broken');
        await assert.rejects(store.save(memory));
        assert.equal(await readFile(filePath, 'utf8'), '{broken');
        await assert.rejects(store.load());
        await writeFile(filePath, JSON.stringify(memory));
        await assert.rejects(store.save(memory), /repair|corrupt/i);
    } finally { await rm(directory, { recursive: true, force: true }); }
});
