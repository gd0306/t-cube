import test from 'node:test';
import assert from 'node:assert/strict';
import { processClipboardText, clipboardTextNotice } from '../src/shared/clipboard-text-processing';

test('cleanup and case conversion preserve the input and handle CRLF and Unicode', () => {
    const source = '  A b \r\n\r\n\r\n 中文\t';
    assert.equal(processClipboardText(source, 'trimLines'), 'A b\n\n\n中文');
    assert.equal(processClipboardText(source, 'collapseBlankLines'), '  A b \n\n 中文\t');
    assert.equal(processClipboardText('Straße 中文', 'uppercase'), 'STRASSE 中文');
    assert.equal(processClipboardText('HELLO 中文', 'lowercase'), 'hello 中文');
    assert.equal(processClipboardText(source, 'original'), source);
});
test('JSON changes only whitespace, preserving huge numbers, duplicate keys and escapes', () => {
    const source = String.raw` {"id":900719925474099312345,"a":[true,null,"a b\n\""],"id":1e400} `;
    const pretty = processClipboardText(source, 'jsonPretty');
    assert.equal(pretty, '{\n  "id": 900719925474099312345,\n  "a": [\n    true,\n    null,\n    "a b\\n\\\""\n  ],\n  "id": 1e400\n}');
    assert.equal(processClipboardText(pretty, 'jsonCompact'), source.trim());
    assert.equal(processClipboardText('42', 'jsonPretty'), '42');
    assert.equal(processClipboardText('[]', 'jsonPretty'), '[]');
    for (const invalid of ['{bad}', '[1,]', '{"a":01}', 'true false', '"\\x"', '{"a":}', '[', '"a\n b"']) assert.throws(() => processClipboardText(invalid, 'jsonPretty'));
});
test('URL component processing round-trips Unicode and keeps literal plus characters', () => {
    const source = '中文 a+b/?=😀';
    assert.equal(processClipboardText(source, 'urlEncode'), '%E4%B8%AD%E6%96%87%20a%2Bb%2F%3F%3D%F0%9F%98%80');
    assert.equal(processClipboardText(processClipboardText(source, 'urlEncode'), 'urlDecode'), source);
    assert.equal(processClipboardText('a+b', 'urlDecode'), 'a+b');
    for (const invalid of ['%', '%Q0', '%FF', '%00']) assert.throws(() => processClipboardText(invalid, 'urlDecode'));
});
test('processing refuses invalid text, oversized output and excessive JSON nesting', () => {
    for (const input of ['\0', 'a'.repeat(65537)]) assert.throws(() => processClipboardText(input, 'original'));
    assert.throws(() => processClipboardText(' \t ', 'trimLines'));
    assert.throws(() => processClipboardText('中'.repeat(8000), 'urlEncode'));
    assert.throws(() => processClipboardText('['.repeat(129) + '0' + ']'.repeat(129), 'jsonPretty'));
    assert.throws(() => processClipboardText('hello', 'unknown' as any));
});


test('host transforms authoritative history text, rejects forged requests and preserves original records', async () => {
    const { ClipboardHistoryRecorder, clipboardHistoryOperations } = await import('../src/main/clipboard-history');
    let sequence = 1;
    const recorder = new ClipboardHistoryRecorder({ sequence: () => sequence, read: async () => '{"id":900719925474099312345}' }, () => {}, () => () => {});
    recorder.setEnabled(true); sequence++; await recorder.poll();
    const original = recorder.state.entries[0];
    const uses: unknown[] = [];
    const operations = clipboardHistoryOperations(recorder, async request => { uses.push(request); return { status: 'copied' }; });
    const request = { id: original.id, action: 'jsonPretty', paste: false };
    await operations.useClipboardHistoryText(request);
    assert.deepEqual(uses, [{ text: '{\n  "id": 900719925474099312345\n}', paste: false }]);
    assert.deepEqual(recorder.state.entries[0], original);
    for (const forged of [{ ...request, text: 'injected' }, { ...request, action: 'unknown' }, { ...request, paste: 'yes' }]) assert.throws(() => operations.useClipboardHistoryText(forged));
    await operations.useClipboardHistoryText({...request, editedText: '编辑后的结果', sourceText: original.text});
    assert.deepEqual(uses.at(-1), {text: '编辑后的结果', paste: false});
    assert.deepEqual(recorder.state.entries[0], original);
    assert.throws(() => operations.useClipboardHistoryText({...request, editedText: 'forged'}));
    recorder.edit(original.id, 'new source');
    assert.throws(() => operations.useClipboardHistoryText({...request, sourceText: original.text}));
    assert.throws(() => operations.editClipboardHistoryEntry({id: original.id, text: 'stale', expectedText: original.text}));
    assert.equal(recorder.state.entries[0].text, 'new source');
    recorder.clear(); assert.throws(() => operations.useClipboardHistoryText(request));
    recorder.dispose();
});

test('no-op conversions and existing percent sequences produce actionable notices', () => {
    for (const action of ['urlEncode', 'urlDecode', 'jsonPretty'] as const) {
        const source = action === 'jsonPretty' ? '42' : 'abc-123';
        const output = processClipboardText(source, action);
        assert.equal(output, source); assert.ok(clipboardTextNotice(source, action, output));
    }
    assert.equal(processClipboardText('a%20b', 'urlEncode'), 'a%2520b');
    assert.match(clipboardTextNotice('a%20b', 'urlEncode', 'a%2520b')!, /%25/);
    assert.equal(clipboardTextNotice('中文', 'urlEncode', processClipboardText('中文', 'urlEncode')), undefined);
});
