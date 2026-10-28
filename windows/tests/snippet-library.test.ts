import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fullSnippetText, filteredSnippets, validateSnippetLibrary } from '../src/core/snippet-library';
import { SnippetStore } from '../src/core/snippet-store';
import { ContentLibraryService } from '../src/main/content-library';
import type { TextSnippet } from '../src/shared/productivity';
const one: TextSnippet = { id: '11111111-1111-4111-8111-111111111111', title: 'Office', group: 'Work', body: 'Hello', fields: [{ id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', label: 'Email', value: 'me@example.com' }], isFavorite: false };
const two: TextSnippet = { ...one, id: '22222222-2222-4222-8222-222222222222', title: 'Café', fields: [], isFavorite: true };
test('Mac-compatible text and accent-insensitive search preserve favorite order', () => {
    assert.equal(fullSnippetText(one), 'Hello\nEmail：me@example.com');
    assert.deepEqual(filteredSnippets({ version: 1, items: [one, two] }, { query: '' }).map(item => item.id), [two.id, one.id]);
    assert.deepEqual(filteredSnippets({ version: 1, items: [one, two] }, { query: 'cafe', group: 'Work' }).map(item => item.id), [two.id]);
    assert.deepEqual(filteredSnippets({ version: 1, items: [one] }, { query: 'EXAMPLE' }).map(item => item.id), [one.id]);
});
test('validation rejects malformed, duplicate and oversized payloads', () => {
    for (const invalid of [null, { version: 2, items: [] }, { version: 1, items: [one, one] }, { version: 1, items: [{ ...one, title: ' ' }] }, { version: 1, items: [{ ...one, body: '', fields: [] }] }, { version: 1, items: [{ ...one, fields: [{ ...one.fields[0], label: '' }] }] }, { version: 1, items: [{ ...one, body: 'x'.repeat(262145) }] }, { version: 1, items: [{ ...one, isFavorite: 'true' }] }, { version: 1, items: [one, { ...two, fields: one.fields }] }]) assert.throws(() => validateSnippetLibrary(invalid));
});
test('serialized library edits persist without lost updates and reload imported data', async () => {
    const directory = await mkdtemp(join(tmpdir(), 'tcube-library-'));
    try {
        const filePath = join(directory, 'content-library.json');
        const service = new ContentLibraryService(new SnippetStore(filePath));
        await Promise.all([service.save(one), service.save(two)]);
        assert.equal((await service.get()).items.length, 2);
        await service.move({ id: one.id, neighborId: two.id });
        assert.deepEqual((await service.get()).items.map(item => item.id), [one.id, two.id]);
        const third = { ...two, id: '33333333-3333-4333-8333-333333333333', isFavorite: false };
        await service.save(third);
        await service.move({ id: third.id, neighborId: one.id });
        assert.deepEqual((await service.get()).items.map(item => item.id), [third.id, two.id, one.id]);
        await service.delete(two.id);
        assert.equal(JSON.parse(await readFile(filePath, 'utf8')).items.length, 2);
        await writeFile(filePath, JSON.stringify({ version: 1, items: [two] }));
        await service.reload();
        assert.deepEqual((await service.get()).items.map(item => item.id), [two.id]);
        assert.deepEqual(await readdir(directory), ['content-library.json']);
    } finally { await rm(directory, { recursive: true, force: true }); }
});
test('corruption preserves bytes and blocks cached edits until explicit successful reload', async () => {
    const directory = await mkdtemp(join(tmpdir(), 'tcube-library-'));
    try {
        const filePath = join(directory, 'content-library.json');
        const service = new ContentLibraryService(new SnippetStore(filePath));
        await service.save(one);
        await writeFile(filePath, '{broken');
        await assert.rejects(service.save(two));
        assert.equal(await readFile(filePath, 'utf8'), '{broken');
        await writeFile(filePath, JSON.stringify({ version: 1, items: [one] }));
        await assert.rejects(service.delete(one.id), /repair|reload|corrupt/i);
        await service.reload();
        assert.equal((await service.save(two)).items.length, 2);
    } finally { await rm(directory, { recursive: true, force: true }); }
});

test('whole-snippet text cannot exceed the explicit clipboard IPC limit', () => {
    assert.throws(() => validateSnippetLibrary({ version: 1, items: [{ ...one, body: 'x'.repeat(262140) }] }));
});
