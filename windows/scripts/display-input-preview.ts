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
try {
    await mkdir('.cache/display-input-preview', { recursive: true });
    for (const theme of ['light', 'dark'] as const) {
        const page = await browser.newPage({ viewport: { width: 400, height: 520 }, colorScheme: theme });
        await page.addInitScript({ content: `
            const identity = 'preview-monitor';
            window.displayInput = {
                list: async () => ({ result: { status: 'listed', displays: [{ identity, name: 'Studio monitor', reading: { current: 5, maximum: 14 } }] }, mappings: { [identity]: { typeC: 7, hdmi: 5 } } }),
                save: async () => ({ status: 'listed', displays: [] }), switch: async () => window.fixtureResult, close: async () => {}
            };` });
        page.on('pageerror', error => console.error(error));
        await page.goto(`http://127.0.0.1:${address.port}/display-input.html`);
        for (const scenario of [
            { status: 'confirmed', reading: { current: 7, maximum: 14 }, text: '输入源已切换。', current: 'Type-C', disabled: false },
            { status: 'no-op', reading: { current: 5, maximum: 14 }, text: '当前已使用此输入源。', current: 'HDMI', disabled: false },
            { status: 'not-applied', reading: { current: 5, maximum: 14 }, text: '显示器没有切换输入源。', current: 'HDMI', disabled: false },
            { status: 'sent-unconfirmed', text: '切换请求未确认，可能已执行；请查看画面。', current: '无法读取', disabled: true }
        ]) {
            await page.reload(); await page.locator('#source:not([disabled])').waitFor();
            assert.match(await page.locator('#current').innerText(), /当前输入源：HDMI/);
            if (scenario.status === 'confirmed') await page.screenshot({ path: `.cache/display-input-preview/${theme}-generic.png`, fullPage: true });
            await page.evaluate(value => { (window as unknown as { fixtureResult: unknown }).fixtureResult = value; }, scenario);
            await page.locator('#source').focus(); await page.keyboard.press('ArrowLeft');
            await page.getByText(scenario.text).waitFor();
            assert.equal(await page.locator('#source').isDisabled(), scenario.disabled);
            assert.match(await page.locator('#current').innerText(), new RegExp(scenario.current));
            if (scenario.status === 'sent-unconfirmed') await page.screenshot({ path: `.cache/display-input-preview/${theme}-unconfirmed.png`, fullPage: true });
        }
        await page.close();
    }
} finally { await browser.close(); server.close(); }
