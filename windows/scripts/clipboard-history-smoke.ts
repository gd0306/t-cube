import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import koffi from 'koffi';
import type { ElectronApplication, Page } from 'playwright';

async function waitFor(check: () => Promise<boolean>, label: string): Promise<void> {
    const deadline = Date.now() + 8000;
    while (Date.now() < deadline) { if (await check()) return; await new Promise(resolve => setTimeout(resolve, 50)); }
    throw new Error(label); // Never include clipboard values in failure diagnostics.
}
/** Called only inside the owned office smoke, while its isolated clipboard snapshot is held. */
export async function verifyClipboardHistorySmoke(app: ElectronApplication, widget: Page, library: Page,
    readReceiver: () => string): Promise<string[]> {
    if (process.platform !== 'win32') return [];
    const isolated = await app.evaluate(({ app }) => ({ actual: app.getPath('userData'), expected: process.env.TCUBE_USER_DATA_DIR }));
    assert.ok(isolated.expected); assert.equal(path.resolve(isolated.actual), path.resolve(isolated.expected));
    const state = () => library.evaluate(() => window.tcube.getClipboardHistory());
    const initial = await state(); assert.equal(initial.isEnabled, false); assert.equal(initial.entries.length, 0);
    const marker = `T-Cube owned history ${randomUUID()}`, text = ` ${marker}\nsecond line `, other = `${marker} other`;
    const user = koffi.load('user32.dll');
    const register = user.func('uint32_t __stdcall RegisterClipboardFormatW(str16 name)');
    const hasFormat = user.func('int __stdcall IsClipboardFormatAvailable(uint32_t format)');
    let savedId: string | undefined;
    // Chromium's CDP dialog.accept can acknowledge a confirm while Electron's
    // native Windows message box remains open. Supply only the two explicit
    // confirmation choices in this disposable renderer; production UI is untouched.
    const confirmationKey = `tcubeOwnedConfirm_${randomUUID().replaceAll('-', '')}`;
    const expectedConfirmations = ['当前编辑尚未保存，放弃修改？', '清空本次运行的全部剪贴板历史？'];
    await library.evaluate(({ key, allowed }) => {
        const state = { original: window.confirm, seen: [] as string[] };
        (window as unknown as Record<string, unknown>)[key] = state;
        window.confirm = message => {
            if (!allowed.includes(String(message))) throw new Error('Unexpected confirmation in owned history fixture');
            state.seen.push(String(message));
            return true;
        };
    }, { key: confirmationKey, allowed: expectedConfirmations });
    try {
        await widget.evaluate(() => window.tcube.showLibrary());
        await library.getByRole('button', { name: '常用内容', exact: true }).click();
        await library.locator('#add').click();
        await library.getByRole('textbox', { name: '标题', exact: true }).fill('Owned unsaved history smoke');
        await library.getByRole('textbox', { name: '正文', exact: true }).fill('Owned draft remains while browsing history');
        await library.getByRole('button', { name: '剪贴板历史', exact: true }).click();
        await app.evaluate(async ({ clipboard }, text) => { await clipboard.writeText(text); }, `${marker} baseline`);
        await library.getByRole('button', { name: '启用记录', exact: true }).click();
        await new Promise(resolve => setTimeout(resolve, 700));
        assert.equal((await state()).entries.length, 0, 'Enabling must skip the existing clipboard');
        await app.evaluate(async ({ clipboard }, text) => { await clipboard.writeText(text); }, text);
        await waitFor(async () => (await state()).entries.length === 1, 'Owned copy was not recorded');
        await app.evaluate(async ({ clipboard }, text) => { await clipboard.writeText(text); }, other);
        await waitFor(async () => (await state()).entries.length === 2, 'Second owned copy was not recorded');
        await app.evaluate(async ({ clipboard }, text) => { await clipboard.writeText(text); }, text);
        await waitFor(async () => (await state()).entries[0]?.text === text, 'Exact duplicate was not promoted');
        assert.equal((await state()).entries.length, 2);
        for (const [format, bytes] of [['ExcludeClipboardContentFromMonitorProcessing', [1]], ['CanIncludeInClipboardHistory', [0, 0, 0, 0]]] as const) {
            await app.evaluate(async ({ clipboard, ClipboardItem }, fixture) => {
                await clipboard.write([new ClipboardItem({ 'text/plain': new Blob([fixture.text]),
                    [`electron application/osclipboard;format="${fixture.format}"`]: new Blob([new Uint8Array(fixture.bytes)]) })]);
            }, { format, bytes: [...bytes], text: `${marker} excluded fixture` });
            assert.ok(hasFormat(register(format)), 'Fixture must expose a real native registered exclusion format');
            await new Promise(resolve => setTimeout(resolve, 750));
            assert.equal((await state()).entries.length, 2, 'Native exclusion marker was not honored');
        }
        await app.evaluate(async ({ clipboard, ClipboardItem }, fixture) => {
            await clipboard.write([new ClipboardItem({ 'text/plain': new Blob([fixture]), 'text/uri-list': new Blob(['file:///C:/T-Cube-owned-history-fixture.txt']) })]);
        }, `${marker} file fixture`);
        assert.ok(hasFormat(15), 'File-list fixture must expose native CF_HDROP');
        await new Promise(resolve => setTimeout(resolve, 750)); assert.equal((await state()).entries.length, 2);
        await library.getByRole('button', { name: '常用内容', exact: true }).click();
        assert.equal(await library.getByRole('textbox', { name: '正文', exact: true }).inputValue(), 'Owned draft remains while browsing history');
        await library.getByRole('button', { name: '剪贴板历史', exact: true }).click();
        await library.getByRole('searchbox', { name: '搜索剪贴板历史', exact: true }).fill('second line');
        await library.getByRole('button', { name: '复制历史文字', exact: true }).click();
        await new Promise(resolve => setTimeout(resolve, 700)); assert.equal((await state()).entries.length, 2, 'App copy must not record itself');
        const receiverBefore = readReceiver();
        await library.getByRole('button', { name: '粘贴历史文字', exact: true }).click();
        await waitFor(async () => readReceiver() === receiverBefore + text, 'History paste did not reach the owned receiver');
        await widget.evaluate(() => window.tcube.showClipboardHistory());
        await library.getByRole('button', { name: '整理为常用内容', exact: true }).click();
        assert.equal(await library.getByRole('textbox', { name: '正文', exact: true }).inputValue(), text);
        await library.getByRole('textbox', { name: '标题', exact: true }).fill('Owned saved history smoke');
        await library.getByRole('button', { name: '保存内容', exact: true }).click();
        await waitFor(async () => (await library.evaluate(() => window.tcube.getLibrary())).items.some(item => item.title === 'Owned saved history smoke'), 'History draft did not save as an ordinary snippet');
        savedId = (await library.evaluate(() => window.tcube.getLibrary())).items.find(item => item.title === 'Owned saved history smoke')?.id;
        await library.getByRole('button', { name: '剪贴板历史', exact: true }).click();
        await library.getByRole('button', { name: '暂停记录', exact: true }).click();
        await app.evaluate(async ({ clipboard }, text) => { await clipboard.writeText(text); }, `${marker} paused fixture`);
        await new Promise(resolve => setTimeout(resolve, 700)); assert.equal((await state()).entries.length, 2);
        await library.getByRole('button', { name: '恢复记录', exact: true }).click();
        await new Promise(resolve => setTimeout(resolve, 700)); assert.equal((await state()).entries.length, 2);
        await library.getByRole('button', { name: '删除历史', exact: true }).click();
        await waitFor(async () => (await state()).entries.length === 1, 'History delete did not remove the selected entry');
        await library.getByRole('button', { name: '清空历史', exact: true }).click();
        await waitFor(async () => (await state()).entries.length === 0, 'History clear did not empty session state');
        const confirmations = await library.evaluate(key => ((window as unknown as Record<string, { seen: string[] }>)[key]).seen, confirmationKey);
        assert.deepEqual(confirmations, expectedConfirmations, 'History must request both explicit confirmation choices');
        return ['Opt-in sequence baselines, owned clipboard recording/dedupe, real native privacy/file exclusions, pause/resume, history copy/paste into owned receiver, draft retention and explicit snippet save passed.'];
    } finally {
        if (!library.isClosed()) await library.evaluate(key => {
            const globals = window as unknown as Record<string, { original: typeof window.confirm }>;
            if (globals[key]) { window.confirm = globals[key].original; delete globals[key]; }
        }, confirmationKey);
        await library.evaluate(() => window.tcube.setClipboardHistoryEnabled(false));
        await library.evaluate(() => window.tcube.clearClipboardHistory());
        if (savedId) await library.evaluate(id => window.tcube.deleteSnippet(id), savedId);
    }
}
