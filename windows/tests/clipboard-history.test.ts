import assert from 'node:assert/strict';
import test from 'node:test';

test('history promotes exact duplicates, preserves whitespace and enforces UTF-8 item/count/total budgets', async () => {
    const { ClipboardHistory } = await import('../src/core/clipboard-history');
    const history = new ClipboardHistory();
    history.add(' first \n'); const original = history.snapshot()[0];
    history.add('second'); history.add(' first \n');
    assert.equal(history.snapshot()[0].id, original.id);
    assert.equal(history.snapshot()[0].text, ' first \n');
    assert.equal(history.snapshot().length, 2);
    for (const text of ['', ' \n\t', 'a\0b', '界'.repeat(21846)]) assert.equal(history.add(text), false);
    for (let index = 0; index < 110; index++) history.add(`Item ${index}`);
    assert.equal(history.snapshot().length, 100);
    assert.equal(history.snapshot().at(-1)?.text, 'Item 10');
    history.clear();
    for (let index = 0; index < 40; index++) history.add(`${String(index).padStart(2, '0')}${'x'.repeat(65534)}`);
    assert.equal(history.snapshot().length, 32);
    assert.equal(history.totalBytes, 2 * 1024 * 1024);
    const id = history.snapshot()[0].id; history.delete(id);
    assert.equal(history.snapshot().length, 31);
    history.clear(); assert.equal(history.totalBytes, 0);
});

test('recorder defaults off, baselines enable/resume and checks sequence before reading', async () => {
    const { ClipboardHistoryRecorder } = await import('../src/main/clipboard-history');
    let sequence = 1, reads = 0, timer: (() => void) | undefined, interval = 0;
    const recorder = new ClipboardHistoryRecorder({ sequence: () => sequence, read: async () => { reads++; return 'owned test text'; } }, () => {}, (callback, milliseconds) => { timer = callback; interval = milliseconds; return () => { timer = undefined; }; });
    await recorder.poll(); assert.equal(reads, 0); assert.equal(recorder.state.isEnabled, false);
    recorder.setEnabled(true); assert.equal(interval, 500);
    await recorder.poll(); assert.equal(reads, 0);
    sequence++; await recorder.poll(); assert.equal(recorder.state.entries.length, 1);
    await recorder.poll(); assert.equal(reads, 1);
    recorder.setEnabled(false); assert.equal(timer, undefined);
    sequence++; recorder.setEnabled(true); await recorder.poll(); assert.equal(reads, 1);
    recorder.dispose(); assert.equal(timer, undefined); assert.deepEqual(recorder.state.entries, []);
});

test('pause, clear, changed sequence and app clipboard writes prevent late read admission', async () => {
    const { ClipboardHistoryRecorder } = await import('../src/main/clipboard-history');
    for (const action of ['pause', 'clear', 'sequence', 'write', 'dispose']) {
        let sequence = 1, finish!: (text: string) => void;
        const recorder = new ClipboardHistoryRecorder({ sequence: () => sequence, read: () => new Promise(resolve => { finish = resolve; }) }, () => {}, () => () => {});
        recorder.setEnabled(true); sequence++;
        const pending = recorder.poll();
        if (action === 'pause') recorder.setEnabled(false);
        if (action === 'clear') recorder.clear();
        if (action === 'sequence') sequence++;
        if (action === 'write') await recorder.performOwnWrite(async () => { sequence++; });
        if (action === 'dispose') recorder.dispose();
        finish('owned delayed text'); await pending;
        assert.deepEqual(recorder.state.entries, [], action);
        recorder.dispose();
    }
});

test('sampling stays suppressed throughout a delayed or failed self write and later external copies still record', async () => {
    const { ClipboardHistoryRecorder } = await import('../src/main/clipboard-history');
    let sequence = 1, reads = 0, finish!: () => void;
    const recorder = new ClipboardHistoryRecorder({ sequence: () => sequence, read: async () => { reads++; return 'owned external copy'; } }, () => {}, () => () => {});
    recorder.setEnabled(true);
    const write = recorder.performOwnWrite(() => new Promise<void>(resolve => { finish = resolve; }));
    sequence++; await recorder.poll(); assert.equal(reads, 0);
    finish(); await write; await recorder.poll(); assert.equal(reads, 0);
    await assert.rejects(recorder.performOwnWrite(async () => { sequence++; throw Error('write failed'); }));
    await recorder.poll(); assert.equal(reads, 0);
    sequence++; await recorder.poll(); assert.equal(reads, 1);
    recorder.dispose();
});

test('Windows exclusion flags and file formats are checked before retrieving any plain text', async () => {
    const { readHistoryClipboardItems } = await import('../src/main/history-clipboard-reader');
    const raw = (name: string) => `electron application/osclipboard;format="${name}"`;
    function item(types: string[], flag = new Uint8Array([0, 0, 0, 0])) {
        let textReads = 0;
        return { get textReads() { return textReads; }, types, getType: async (type: string) => {
            if (type === 'text/plain') { textReads++; return new Blob(['owned policy sample']); }
            if (type === 'text/uri-list') return new Blob(['file:///C:/owned.txt']);
            return new Blob([flag]);
        } };
    }
    for (const format of ['text/uri-list', raw('CF_HDROP'), raw('ExcludeClipboardContentFromMonitorProcessing'), raw('CanIncludeInClipboardHistory')]) {
        const sample = item(['text/plain', format]);
        assert.equal(await readHistoryClipboardItems([sample]), null);
        assert.equal(sample.textReads, 0);
    }
    const allowed = item(['text/plain', raw('CanIncludeInClipboardHistory')], new Uint8Array([1, 0, 0, 0]));
    assert.equal(await readHistoryClipboardItems([allowed]), 'owned policy sample');
    const cloudOnly = item(['text/plain', raw('CanUploadToCloudClipboard')]);
    assert.equal(await readHistoryClipboardItems([cloudOnly]), 'owned policy sample');
    const first = item(['text/plain']), protectedSecond = item([raw('ExcludeClipboardContentFromMonitorProcessing')]);
    assert.equal(await readHistoryClipboardItems([first, protectedSecond]), null); assert.equal(first.textReads, 0);
});

test('native clipboard reader rejects oversized and malformed format payloads before text decoding', async () => {
    const { readHistoryClipboardItems } = await import('../src/main/history-clipboard-reader');
    let decoded = false;
    const oversized = new Blob(['x'.repeat(65537)]);
    oversized.text = async () => { decoded = true; throw Error('must not decode'); };
    assert.equal(await readHistoryClipboardItems([{ types: ['text/plain'], getType: async () => oversized }]), null);
    assert.equal(decoded, false);
    const flag = 'electron application/osclipboard;format="CanIncludeInClipboardHistory"';
    assert.equal(await readHistoryClipboardItems([{ types: ['text/plain', flag], getType: async () => new Blob(['x']) }]), null);
});

test('Win32 format policy rejects file drops and native history exclusions independently of Electron MIME conversion', async () => {
    const { historyFormatsAllowed } = await import('../src/native/clipboard-history');
    const ids = new Map([['ExcludeClipboardContentFromMonitorProcessing', 40001], ['CanIncludeInClipboardHistory', 40002]]);
    for (const [present, value, expected] of [[[15], 1, false], [[40001], 1, false], [[40002], 0, false], [[40002], null, false], [[40002], 1, true], [[], 0, true]] as const) {
        const bindings = { register: (name: string) => ids.get(name)!, has: (id: number) => (present as readonly number[]).includes(id), readDWORD: () => value };
        assert.equal(historyFormatsAllowed(bindings), expected);
    }
});

test('history operations validate all payloads and use only the selected recorded text', async () => {
    const { ClipboardHistoryRecorder, clipboardHistoryOperations } = await import('../src/main/clipboard-history');
    let sequence = 1;
    const recorder = new ClipboardHistoryRecorder({ sequence: () => sequence, read: async () => 'owned operation fixture' }, () => {}, () => () => {});
    const uses: unknown[] = [];
    const operations = clipboardHistoryOperations(recorder, async request => { uses.push(request); return { status: 'done' }; });
    for (const [operation, payload] of [['getClipboardHistory', {}], ['setClipboardHistoryEnabled', 'yes'], ['clearClipboardHistory', true], ['deleteClipboardHistoryEntry', 'unknown'], ['useClipboardHistoryEntry', { id: 'bad', paste: true }]] as const) {
        assert.throws(() => operations[operation](payload));
    }
    operations.setClipboardHistoryEnabled(true); sequence++; await recorder.poll();
    const entry = recorder.state.entries[0];
    await operations.useClipboardHistoryEntry({ id: entry.id, paste: false });
    assert.deepEqual(uses, [{ text: 'owned operation fixture', paste: false }]);
    operations.deleteClipboardHistoryEntry(entry.id);
    assert.throws(() => operations.useClipboardHistoryEntry({ id: entry.id, paste: true }));
    assert.equal(uses.length, 1);
    recorder.dispose();
});

test('HTTP URI lists preserve their plain-text URL while file URI lists and nontext payloads stay excluded', async () => {
    const { readHistoryClipboardItems } = await import('../src/main/history-clipboard-reader');
    for (const address of ['https://example.test/owned', 'http://example.test/owned']) {
        const item = { types: ['text/uri-list', 'text/plain'], getType: async () => new Blob([address]) };
        assert.equal(await readHistoryClipboardItems([item]), address);
    }
    const files = { types: ['text/uri-list', 'text/plain'], getType: async (type: string) => new Blob([type === 'text/uri-list' ? '# files\r\nfile:///C:/owned.txt\r\n' : 'C:\\owned.txt']) };
    assert.equal(await readHistoryClipboardItems([files]), null);
    assert.equal(await readHistoryClipboardItems([{ types: ['image/png'], getType: async () => { throw Error('Do not retrieve image payload'); } }]), null);
});

test('privacy or sequence invalidation after metadata prevents requesting plain text payloads', async () => {
    const { readHistoryClipboardItems } = await import('../src/main/history-clipboard-reader');
    let current = false, textRequests = 0;
    const item = { types: ['text/plain'], getType: async () => { textRequests++; return new Blob(['owned changed snapshot']); } };
    assert.equal(await readHistoryClipboardItems([item], () => current), null);
    assert.equal(textRequests, 0);
    const flag = 'electron application/osclipboard;format="CanIncludeInClipboardHistory"';
    current = true;
    const changesDuringFlag = { types: [flag, 'text/plain'], getType: async (type: string) => {
        if (type === 'text/plain') { textRequests++; return new Blob(['owned changed snapshot']); }
        current = false; return new Blob([new Uint8Array([1, 0, 0, 0])]);
    } };
    assert.equal(await readHistoryClipboardItems([changesDuringFlag], () => current), null);
    assert.equal(textRequests, 0);
});

test('sequence invalidation while fetching the text blob prevents decoding it', async () => {
    const { readHistoryClipboardItems } = await import('../src/main/history-clipboard-reader');
    let current = true, decoded = false;
    const blob = new Blob(['owned delayed blob']);
    blob.text = async () => { decoded = true; return 'owned delayed blob'; };
    const item = { types: ['text/plain'], getType: async () => { current = false; return blob; } };
    assert.equal(await readHistoryClipboardItems([item], () => current), null);
    assert.equal(decoded, false);
});

test('recorder threads its sequence validity through delayed metadata before text payload access', async () => {
    const { ClipboardHistoryRecorder } = await import('../src/main/clipboard-history');
    const { readHistoryClipboardItems } = await import('../src/main/history-clipboard-reader');
    let sequence = 1, release!: () => void, textRequests = 0;
    const item = { types: ['text/plain'], getType: async () => { textRequests++; return new Blob(['owned raced metadata']); } };
    const recorder = new ClipboardHistoryRecorder({ sequence: () => sequence, read: async current => {
        await new Promise<void>(resolve => { release = resolve; });
        return readHistoryClipboardItems([item], current);
    } }, () => {}, () => () => {});
    recorder.setEnabled(true); sequence++;
    const pending = recorder.poll(); sequence++; release(); await pending;
    assert.equal(textRequests, 0);
    assert.deepEqual(recorder.state.entries, []);
    recorder.dispose();
});

test('production recorder constructs with its default timer while recording remains off', async () => {
    const { ClipboardHistoryRecorder } = await import('../src/main/clipboard-history');
    let reads = 0, notifications = 0;
    const recorder = new ClipboardHistoryRecorder({ sequence: () => 1, read: async () => { reads++; return 'must not read'; } }, () => { notifications++; });
    assert.equal(recorder.state.isEnabled, false);
    assert.deepEqual(recorder.state.entries, []);
    await recorder.poll();
    assert.equal(reads, 0);
    assert.equal(notifications, 0);
    recorder.dispose();
});
