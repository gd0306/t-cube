// Isolated renderer acceptance: no native targets or user files.
import { chromium } from 'playwright';
import { createServer } from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import { defaultConfiguration } from '../src/core/configuration';
const root = path.resolve('dist');
const server = createServer((request, response) => {
    const file = path.resolve(root, '.' + (request.url ?? ''));
    if (!file.startsWith(root + path.sep)) { response.writeHead(403).end(); return; }
    const types: Record<string, string> = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png' };
    void readFile(file).then(data => response.writeHead(200, { 'content-type': types[path.extname(file)] ?? 'application/octet-stream' }).end(data), () => response.writeHead(404).end());
});
await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve));
const address = server.address();
if (!address || typeof address === 'string') throw new Error('Missing preview address');
const browser = await chromium.launch({ headless: true, channel: 'chrome' });
try {
    await mkdir('.cache/settings-preview', { recursive: true });
    for (const theme of ['light', 'dark'] as const) for (const width of [800, 1060]) {
        const page = await browser.newPage({ viewport: { width, height: 740 }, colorScheme: theme });
        const errors: string[] = [];
        page.on('pageerror', e => { errors.push(e.message); console.error('Renderer:', e.message); });
        page.setDefaultTimeout(5000);
        const config = defaultConfiguration();
        config.groups.front.name = '保留我的入口'; config.scale = 1.3; config.hover.multiplier = 2.5;
        config.windowPosition = { x: 123, y: 456 };
        // tsx preserves function names with this helper when serializing callbacks.
        await page.addInitScript({ content: 'globalThis.__name = (value) => value;' });
        await page.addInitScript(configuration => {
            const fixture = { configuration, saves: 0 };
            (window as any).fixture = fixture;
            const state = () => ({ configuration: fixture.configuration });
            const listeners: Array<(value: unknown) => void> = [];
            (window as any).tcube = {
                onError: () => {}, onIcons: () => {}, onState: (fn: (value: unknown) => void) => listeners.push(fn),
                getSnapshot: async () => ({ state: state(), icons: {} }),
                applyConfiguration: async (next: typeof configuration) => { fixture.configuration = next; fixture.saves++; for (const fn of listeners) fn(state()); },
                getPerformanceSettings: async () => ({ idlePowerSaving: true }),
                getMaintenanceState: async () => ({ backups: [], broken: [], status: '本地入口检查完成。' }),
                getLifecycleState: async () => ({ version: '0.22.8', updateMode: 'reminder', loginEnabled: true, loginSupported: true, automaticUpdates: true, checksSupported: true, status: '已开启版本提醒。' }),
            };
        }, config);
        await page.goto(`http://127.0.0.1:${address.port}/renderer/settings.html`);
        await page.getByRole('heading', { name: '立方体入口' }).waitFor();
        for (const id of ['groups', 'appearance', 'behavior', 'performance', 'maintenance', 'lifecycle']) {
            await page.locator(`nav [data-page="${id}"]`).click();
            assert.equal(await page.locator('nav [aria-current="page"]').count(), 1);
            assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth && document.querySelector('.detail')!.scrollWidth <= document.querySelector('.detail')!.clientWidth), true, `${id} overflow ${theme}/${width}`);
            await page.screenshot({ path: `.cache/settings-preview/${theme}-${width}-${id}.png` });
        }
        await page.locator('nav [data-page="appearance"]').click();
        await page.getByLabel('材质', { exact: true }).selectOption('slime');
        await page.waitForFunction(() => (window as any).fixture.configuration.appearance.material === 'slime');
        await page.getByRole('button', { name: '恢复默认外观', exact: true }).click();
        await page.waitForFunction(() => (window as any).fixture.configuration.appearance.material === 'glass');
        const saved = await page.evaluate(() => (window as any).fixture.configuration);
        assert.deepEqual(saved.groups, config.groups); assert.deepEqual(saved.windowPosition, config.windowPosition);
        assert.deepEqual(saved.hover, config.hover); assert.equal(saved.scale, config.scale);
        assert.deepEqual(saved.appearance, defaultConfiguration().appearance); assert.deepEqual(saved.themeCycle, defaultConfiguration().themeCycle);
        await page.emulateMedia({ forcedColors: 'active', reducedMotion: 'reduce' });
        await page.locator('nav [data-page="behavior"]').focus(); await page.keyboard.press('Enter');
        assert.equal(await page.locator('nav [data-page="behavior"]').getAttribute('aria-current'), 'page');
        assert.deepEqual(errors, []); await page.close();
    }
    console.log('Settings: six pages × two sizes × light/dark; no overflow, keyboard navigation, forced colors, immediate save and scoped defaults passed.');
} finally { await browser.close(); server.close(); }
