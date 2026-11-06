// Isolated renderer smoke: no Electron main process, native driver, or user files.
import { chromium } from 'playwright';
import { createServer } from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
const root = path.resolve('dist/renderer');
const files: Record<string, string> = { '/display-input.html': 'text/html', '/display-input.js': 'text/javascript', '/display-input.css': 'text/css' };
const server = createServer((request, response) => {
    const name = request.url ?? ''; if (!files[name]) { response.writeHead(404).end(); return; }
    void readFile(path.join(root, name)).then(data => { response.writeHead(200, { 'content-type': files[name] }); response.end(data); }, () => response.writeHead(404).end());
});
await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve));
const address = server.address(); if (!address || typeof address === 'string') throw new Error('No preview port');
const browser = await chromium.launch({ headless: true, channel: 'chrome' });
interface Fixture { requests: { id: string; target: string }[]; result: unknown; complete(): void }
type PreviewWindow = Window & { fixture: Fixture };
try {
    await mkdir('.cache/display-input-preview', { recursive: true });
    for (const theme of ['light', 'dark'] as const) {
        const page = await browser.newPage({ viewport: { width: 400, height: 520 }, colorScheme: theme });
        page.setDefaultTimeout(5000);
        const errors: string[] = [];
        page.on('pageerror', error => errors.push(error.message));
        await page.addInitScript({ content: `
            const identity = 'preview-monitor';
            window.fixture = { requests: [], result: null, complete: null };
            window.displayInput = {
                list: async () => ({ result: { status: 'listed', displays: [{ identity, name: 'Studio monitor', reading: { current: 5, maximum: 14 } }] }, mappings: { [identity]: { typeC: 7, hdmi: 5 } } }),
                save: async () => {}, close: async () => {},
                switch: (id, target) => {
                    window.fixture.requests.push({id, target});
                    return new Promise(resolve => { window.fixture.complete = () => resolve(window.fixture.result); });
                }
            };` });
        for (const scenario of [
            { status: 'confirmed', reading: { current: 7, maximum: 14 }, text: '输入源已切换。', checked: 'typeC', disabled: false },
            { status: 'no-op', reading: { current: 7, maximum: 14 }, text: '当前已使用此输入源。', checked: 'typeC', disabled: false },
            { status: 'not-applied', reading: { current: 5, maximum: 14 }, text: '显示器没有切换输入源。', checked: 'hdmi', disabled: false },
            { status: 'sent-unconfirmed', text: '切换请求未确认，可能已执行；请查看画面。', checked: null, disabled: true }
        ]) {
            await page.goto(`http://127.0.0.1:${address.port}/display-input.html`);
            const group = page.getByRole('radiogroup', { name: '输入源', exact: true });
            const left = page.getByRole('radio', { name: 'Type-C', exact: true });
            const right = page.getByRole('radio', { name: 'HDMI', exact: true });
            await group.waitFor(); await page.locator('#source:not([disabled])').waitFor();
            assert.equal(await right.isChecked(), true);
            assert.equal(await left.isChecked(), false);
            await right.click();
            assert.deepEqual(await page.evaluate(() => (window as unknown as PreviewWindow).fixture.requests), []);
            if (scenario.status === 'confirmed') await page.screenshot({ path: `.cache/display-input-preview/${theme}-generic.png`, fullPage: true, animations: 'disabled' });
            await page.evaluate(value => { (window as unknown as PreviewWindow).fixture.result = value; }, scenario);
            if (scenario.status === 'confirmed') { await right.focus(); await page.keyboard.press('ArrowLeft'); }
            else await left.click();
            assert.equal(await left.isDisabled(), true);
            assert.equal(await right.isDisabled(), true);
            assert.equal(await right.isChecked(), true, 'Keep confirmed input until readback');
            await left.dispatchEvent('change');
            assert.deepEqual(await page.evaluate(() => (window as unknown as PreviewWindow).fixture.requests), [{ id: 'preview-monitor', target: 'typeC' }]);
            await page.evaluate(() => (window as unknown as PreviewWindow).fixture.complete());
            await page.getByText(scenario.text, { exact: true }).waitFor();
            assert.equal(await left.isDisabled(), scenario.disabled);
            assert.equal(await right.isDisabled(), scenario.disabled);
            assert.equal(await left.isChecked(), scenario.checked === 'typeC');
            assert.equal(await right.isChecked(), scenario.checked === 'hdmi');
            if (scenario.status === 'confirmed') {
                await left.focus(); await page.keyboard.press('ArrowRight');
                assert.deepEqual(await page.evaluate(() => (window as unknown as PreviewWindow).fixture.requests), [
                    { id: 'preview-monitor', target: 'typeC' }, { id: 'preview-monitor', target: 'hdmi' }
                ]);
                await page.evaluate(() => {
                    (window as unknown as PreviewWindow).fixture.result = { status: 'confirmed', reading: { current: 5, maximum: 14 } };
                    (window as unknown as PreviewWindow).fixture.complete();
                });
                await page.locator('#source:not([disabled])').waitFor();
                assert.equal(await right.isChecked(), true);
                await page.emulateMedia({ reducedMotion: 'reduce' });
                assert.equal(await page.locator('.source-selection').evaluate(element => getComputedStyle(element).transitionDuration), '0s');
                await page.emulateMedia({ reducedMotion: 'no-preference' });
            }
            if (scenario.status === 'sent-unconfirmed') await page.screenshot({ path: `.cache/display-input-preview/${theme}-unconfirmed.png`, fullPage: true, animations: 'disabled' });
        }
        assert.deepEqual(errors, []);
        await page.close();
    }
} finally { await browser.close(); server.close(); }
