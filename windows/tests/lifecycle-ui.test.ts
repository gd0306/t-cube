import test from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';
import { chromium } from 'playwright';
import { existsSync } from 'node:fs';
const chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
test('unsigned reminder settings expose default-off checks and a manual release page without installation', { skip: !existsSync(chrome) }, async () => {
    const browser = await chromium.launch({ executablePath: chrome, headless: true });
    try {
        const page = await browser.newPage();
        await page.setContent('<main></main>');
        await page.addScriptTag({ content: 'window.__name = (value) => value;' });
        page.setDefaultTimeout(2000);
        await page.evaluate(() => {
            const state = { loginEnabled: false, loginSupported: true, automaticUpdates: false, updatesEnabled: false, updateReady: false, updateMode: 'reminder', checksSupported: true, version: '0.18.1', releaseURL: 'https://github.com/gd0306/t-cube/releases', status: '自动检查默认关闭' };
            (window as any).calls = { checks: 0, opens: 0, login: 0 };
            (window as any).tcube = { getLifecycleState: async () => state, setAutomaticUpdates: async (enabled: boolean) => ({ ...state, automaticUpdates: enabled }), setLoginEnabled: async (enabled: boolean) => { (window as any).calls.login++; return { ...state, loginEnabled: enabled }; }, checkForUpdates: async () => { (window as any).calls.checks++; return { ...state, latestVersion: '0.19.0', status: '发现新版本 0.19.0' }; }, openReleasePage: async () => { (window as any).calls.opens++; } };
        });
        const built = await build({ stdin: { contents: "import {renderLifecycle} from './windows/src/renderer/lifecycle'; renderLifecycle(document.querySelector('main')!);", resolveDir: process.cwd().endsWith('/windows') ? process.cwd().slice(0, -8) : process.cwd(), loader: 'ts' }, bundle: true, write: false, platform: 'browser', format: 'iife' });
        await page.addScriptTag({ content: built.outputFiles[0].text });
        const automatic = page.getByLabel('自动检查新版本（仅提醒）');
        await automatic.waitFor(); assert.equal(await automatic.isChecked(), false); assert.equal(await automatic.isEnabled(), true);
        const check = page.getByRole('button', { name: '检查更新', exact: true }); assert.equal(await check.isEnabled(), true);
        assert.equal(await page.getByRole('button', { name: '重启并安装更新' }).isVisible(), false);
        assert.deepEqual(await page.evaluate(() => (window as any).calls), { checks: 0, opens: 0, login: 0 });
        await check.click(); await page.getByText('发现新版本 0.19.0', { exact: true }).waitFor(); assert.match(await page.locator('main').innerText(), /最新版本 0.19.0/);
        await page.getByRole('button', { name: '打开发布页面' }).click();
        assert.deepEqual(await page.evaluate(() => (window as any).calls), { checks: 1, opens: 1, login: 0 });
    } finally { await browser.close(); }
});
