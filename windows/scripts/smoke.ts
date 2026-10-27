import assert from 'node:assert/strict';
import { mkdir, mkdtemp, writeFile, rm, copyFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import os from 'node:os';
import path from 'node:path';
import { _electron, type ElectronApplication, type Page } from 'playwright';
import { defaultConfiguration } from '../src/core/configuration.js';
import { FACES, type Configuration } from '../src/shared/contracts.js';
import { nativeInput } from './native-input.js';

const output = path.resolve('.cache/smoke');
await mkdir(output, { recursive: true });
const data = await mkdtemp(path.join(os.tmpdir(), 't-cube-smoke-'));
const configuration = defaultConfiguration();
configuration.windowPosition = { x: 200, y: 150 };
configuration.autoRotatesWhenIdle = false;
const sampleTargets = process.platform === 'win32'
    ? [path.join(process.env.WINDIR!, 'System32/notepad.exe'), path.join(process.env.WINDIR!, 'System32/cmd.exe'), path.join(process.env.WINDIR!, 'explorer.exe'), process.env.WINDIR!]
    : ['/System/Applications/Calculator.app', '/System/Applications/Notes.app', '/System/Applications/Preview.app', '/System/Library/CoreServices/Finder.app'];
// Keep the Windows schema valid on macOS. Preview icons arrive through the normal
// host icon channel; native Windows shell extraction is exercised on Windows only.
const targets = process.platform === 'win32' ? sampleTargets : ['C:\\Preview\\Calculator.exe', 'C:\\Preview\\Notes.exe', 'C:\\Preview\\Preview.exe', 'C:\\Preview\\Finder.exe'];
for (const face of FACES) configuration.groups[face].slots = targets.map((target, slot) => ({ id: `${face}-${slot}`, path: target, name: path.basename(target), kind: slot === 3 && process.platform === 'win32' ? 'folder' : 'application' })) as Configuration['groups']['front']['slots'];
await writeFile(path.join(data, 'configuration.json'), JSON.stringify(configuration));
const results: string[] = [];
let app: ElectronApplication | undefined;
let widget!: Page;
let originalCursor: { x: number; y: number } | undefined;
const input = nativeInput();
let previewIcons: Record<string, string> | undefined;
const catalogExecutable = path.join(data, 'catalog-smoke.exe');
const catalogRegistryKey = `HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\tcube-${path.basename(data)}.exe`;
let catalogRegistered = false;
async function sendPreviewIcons() {
    if (!previewIcons) return;
    await app!.evaluate(({ BrowserWindow }, icons) => {
        for (const window of BrowserWindow.getAllWindows()) window.webContents.send('tcube:icons', icons);
    }, previewIcons);
}

async function until<T>(read: () => Promise<T>, check: (value: T) => boolean, message: string): Promise<T> {
    const deadline = Date.now() + 10_000;
    let last: T;
    do {
        last = await read();
        if (check(last)) return last;
        await new Promise(resolve => setTimeout(resolve, 50));
    } while (Date.now() < deadline);
    throw new Error(`${message}: ${JSON.stringify(last!)}`);
}
async function snapshot() { return widget!.evaluate(() => window.tcube.getSnapshot()); }
async function bounds() {
    return app!.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows().find(win => win.webContents.getURL().endsWith('/widget.html'))!.getBounds());
}
async function move(x: number, y: number) {
    const point = process.platform === 'win32'
        ? await app!.evaluate(({ screen }, point) => screen.dipToScreenPoint(point), { x: Math.round(x), y: Math.round(y) })
        : { x, y };
    input.move(point.x, point.y);
}
async function capture(page: Page, name: string, backdrop = true, background = '#18212e') {
    // A capture-only backdrop makes alpha comparable; the shipping page stays transparent.
    const previous = await page.evaluate(() => document.body.style.background);
    if (backdrop) await page.evaluate(value => { document.body.style.background = value; }, background);
    await page.screenshot({ path: path.join(output, name), animations: 'disabled' });
    await page.evaluate(value => { document.body.style.background = value; }, previous);
}

try {
    if (process.platform === 'win32') {
        await copyFile(path.join(process.env.WINDIR!, 'System32', 'notepad.exe'), catalogExecutable);
        execFileSync('reg.exe', ['ADD', catalogRegistryKey, '/ve', '/t', 'REG_SZ', '/d', catalogExecutable, '/f'], { windowsHide: true });
        catalogRegistered = true;
        execFileSync('reg.exe', ['ADD', catalogRegistryKey, '/v', 'FriendlyAppName', '/t', 'REG_SZ', '/d', 'T-Cube catalog smoke', '/f'], { windowsHide: true });
    }
    const executablePath = process.env.TCUBE_SMOKE_EXECUTABLE;
    app = await _electron.launch({
        executablePath,
        args: [...(executablePath ? [] : [path.resolve('.')]), ...(process.platform === 'win32' ? ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] : [])],
        env: { ...process.env, TCUBE_USER_DATA_DIR: data },
        timeout: 30_000
    });
    originalCursor = await app.evaluate(({ screen }) => screen.getCursorScreenPoint());
    const launchContext = await app.evaluate(({ app }) => ({ directory: app.getPath('userData'), override: process.env.TCUBE_USER_DATA_DIR, appPath: app.getAppPath() }));
    console.log('Smoke launch context:', JSON.stringify(launchContext));
    assert.equal(path.resolve(launchContext.directory), path.resolve(data), 'Electron must use the explicit isolated configuration directory');
    widget = await until(async () => app!.windows(), pages => pages.some(page => page.url().endsWith('/widget.html')), 'Widget was not created').then(pages => pages.find(page => page.url().endsWith('/widget.html'))!);
    const errors: string[] = [];
    widget.on('pageerror', error => errors.push(error.message));
    await until(snapshot, value => value.state.configuration.groups.front.slots.filter(Boolean).length === 4, 'Four targets missing');
    if (process.platform === 'darwin') {
        const samples = await app.evaluate(async ({ app }, targets) => Promise.all(targets.map(async target => (await app.getFileIcon(target, { size: 'large' })).toDataURL())), sampleTargets);
        previewIcons = Object.fromEntries(FACES.flatMap(face => samples.map((url, slot) => [`${face}-${slot}`, url])));
        await sendPreviewIcons();
    }
    await move(2, 2);
    await until(bounds, frame => frame.width === 164, 'Resting size incorrect');
    const contour = await widget.evaluate(async () => {
        const { controller } = await import(new URL('widget.js', location.href).href);
        const faces = controller.cube.children.filter((mesh: any) => mesh.geometry?.getAttribute('position').count === 1089);
        const visibility = faces.map((mesh: any) => mesh.visible);
        try {
            faces.forEach((mesh: any) => { mesh.visible = false; });
            controller.renderer.render(controller.scene, controller.camera);
            const gl = controller.renderer.getContext();
            const { width, height } = controller.renderer.domElement;
            const pixels = new Uint8Array(width * height * 4);
            gl.readPixels(0, 0, width, height, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
            const backgrounds = [[24, 33, 46], [245, 246, 248]];
            const visible = backgrounds.map(background => {
                let count = 0;
                for (let i = 0; i < pixels.length; i += 4) {
                    const alpha = pixels[i + 3] / 255;
                    const contrast = Math.max(...background.map((channel, index) => Math.abs(pixels[i + index] - alpha * channel)));
                    if (contrast >= 18) count++;
                }
                return count / (width * height);
            });
            const middle = ((Math.floor(height / 2) * width) + Math.floor(width / 2)) * 4;
            return { dark: visible[0], light: visible[1], centerAlpha: pixels[middle + 3] / 255 };
        } finally {
            faces.forEach((mesh: any, index: number) => { mesh.visible = visibility[index]; });
            controller.renderer.render(controller.scene, controller.camera);
        }
    });
    console.log('Resting glass contrast:', JSON.stringify(contour));
    assert.ok(contour.dark >= 0.004, 'Glass contour is effectively invisible over a dark desktop');
    assert.ok(contour.light >= 0.004, 'Glass contour is effectively invisible over a light desktop');
    assert.ok(contour.centerAlpha < 0.12, 'The glass center should remain transparent');
    await capture(widget, 'widget-idle-dark.png');
    await capture(widget, 'widget-idle-light.png', true, '#f5f6f8');
    results.push('Resting glass has visible contrast on dark and light desktops with a transparent center.');
    results.push('Loaded isolated six-group configuration and resting geometry.');
    const initial = await bounds();
    await move(initial.x + initial.width / 2, initial.y + initial.height / 2);
    await until(bounds, frame => frame.width === 656, 'Hover did not enlarge to 4x');
    await until(snapshot, value => value.state.hovered, 'Hover state not published');
    if (process.platform === 'win32') await until(snapshot, value => Object.keys(value.icons).length === 24, 'Native target icons did not load');
    assert.equal(await widget.locator('canvas').count(), 1);
    await until(() => widget.evaluate(async () => {
        const { controller } = await import(new URL('widget.js', location.href).href);
        const faces = controller.cube.children.filter((mesh: any) => mesh.geometry?.getAttribute('position').count === 1089);
        return faces.length === 6 && faces.every((mesh: any) => mesh.material.map?.image.data.some((value: number, index: number) => index % 4 === 3 && value > 0));
    }), Boolean, 'Curved face textures are not ready');
    await capture(widget, 'widget-hover.png');
    await capture(widget, 'widget-hover-light.png', true, '#f5f6f8');
    results.push('Native cursor hover enlarged to 4x with configured icons.');

    if (process.platform === 'win32') {
        input.control(true);
        await until(bounds, frame => frame.width === 164, 'Global Ctrl did not shrink inactive window');
        const before = await bounds();
        const pointer = await app.evaluate(({ screen }) => screen.getCursorScreenPoint());
        input.button(0, true);
        await until(snapshot, value => value.state.interactionActive, 'Ctrl drag did not begin');
        input.control(false);
        await move(pointer.x + 240, pointer.y + 130);
        await until(bounds, frame => frame.x > before.x + 160 && frame.width === 164, 'Ctrl drag did not move beyond its original bounds at resting size');
        input.button(0, false);
        await until(snapshot, value => !value.state.interactionActive, 'Outside release did not finish');
        await move(2, 2);
        await until(bounds, frame => frame.width === 164, 'Post-drag resting size incorrect');
        assert.notDeepEqual((await snapshot()).state.configuration.windowPosition, configuration.windowPosition);
        results.push('Inactive-window Ctrl shrink, Ctrl-left drag, Ctrl release mid-drag and native mouse-up persisted position.');
    } else results.push('Native Windows Ctrl/button paths skipped on macOS preview.');

    await widget.evaluate(() => window.tcube.showSettings());
    const settings = await until(async () => app!.windows(), pages => pages.some(page => page.url().endsWith('/settings.html')), 'Settings missing').then(pages => pages.find(page => page.url().endsWith('/settings.html'))!);
    await settings.waitForLoadState('domcontentloaded');
    await until(() => settings.locator('body').innerText(), value => value.includes('T-Cube'), 'Settings not rendered');
    await until(() => settings.locator('.slot').count(), count => count === 4, 'Settings slots not rendered');
    await sendPreviewIcons();
    const nameInput = settings.locator('#group-name');
    await nameInput.fill('Edited group');
    const tab = settings.getByRole('button', { name: '开发', exact: true });
    const tabBounds = await tab.boundingBox();
    assert.ok(tabBounds);
    // One actual press/release, without locator retries that can mask a lost click.
    await settings.mouse.click(tabBounds.x + tabBounds.width / 2, tabBounds.y + tabBounds.height / 2);
    await until(() => nameInput.inputValue(), value => value === '开发', 'First group-tab click was lost after input blur');
    await until(snapshot, value => value.state.configuration.groups.front.name === 'Edited group', 'Blur did not persist the edited group name');
    await settings.evaluate(() => window.tcube.renameGroup({ face: 'front', name: '常用' }));
    results.push('Editing a group name preserves its draft and the first subsequent tab click.');
    if (process.platform === 'win32') {
        await settings.getByRole('button', { name: '添加应用', exact: true }).nth(1).click();
        await settings.keyboard.press('Escape');
        await settings.locator('.application-picker').waitFor({ state: 'hidden' });
        await settings.getByRole('button', { name: '添加应用', exact: true }).first().click();
        const search = settings.getByRole('searchbox', { name: '搜索已安装的应用' });
        await until(() => settings.locator('.application-result').count(), count => count > 1, 'Installed application list is empty');
        await settings.locator('.application-icon img').first().waitFor({ state: 'visible', timeout: 10_000 });
        await capture(settings, 'application-picker-all.png', false);
        await search.fill('T-Cube catalog smoke');
        await settings.getByRole('button', { name: '刷新列表', exact: true }).click();
        await until(() => settings.getByRole('button', { name: '刷新列表', exact: true }).isEnabled(), Boolean, 'Application refresh did not finish');
        const result = settings.locator('.application-result').filter({ hasText: 'T-Cube catalog smoke' }).first();
        await result.waitFor({ state: 'visible', timeout: 30_000 });
        await capture(settings, 'application-picker.png', false);
        await result.click();
        await settings.locator('.application-picker').waitFor({ state: 'hidden' });
        await until(snapshot, value => value.state.configuration.groups.right.slots[0]?.path === catalogExecutable, 'Catalog selection did not reach the requested slot');
        assert.equal((await snapshot()).state.configuration.groups.right.slots[0]?.name, 'T-Cube catalog smoke');
        const catalog = await settings.evaluate(() => window.tcube.listInstalledApplications());
        assert.ok(catalog.length > 1, 'The catalog should include real installed applications');
        const virtual = catalog.find(entry => entry.detail === 'Windows 应用');
        if (virtual) {
            await settings.evaluate(applicationId => window.tcube.addInstalledApplication({ face: 'bottom', slot: 3, applicationId }), virtual.id);
            const shortcutPath = (await snapshot()).state.configuration.groups.bottom.slots[3]!.path;
            const shortcut = await app.evaluate(({ shell }, file) => shell.readShortcutLink(file), shortcutPath);
            assert.match(shortcut.target, /\\explorer\.exe$/i);
            assert.match(shortcut.args ?? '', /^shell:AppsFolder\\/);
            results.push('A registered virtual application produced a native launch shortcut without changing the configuration schema.');
        }
        results.push('Real Windows application discovery, name search and click-to-add passed.');
    }
    const saved = await snapshot();
    const updated = structuredClone(saved.state.configuration);
    updated.expandsFacesOnClick = false;
    updated.hover.multiplier = 2;
    updated.themeCycle = { isEnabled: true, themes: ['ocean', 'sunset'], intervalSeconds: 10 };
    await settings.evaluate(config => window.tcube.applyConfiguration(config), updated);
    await until(snapshot, value => !value.state.configuration.expandsFacesOnClick && value.state.activeTheme === 'ocean', 'Preference change not applied');
    await settings.evaluate(() => window.tcube.place('bottomRight'));
    const placed = (await snapshot()).state.configuration.windowPosition;
    const expected = await app.evaluate(({ screen }, size) => {
        const area = screen.getPrimaryDisplay().workArea;
        return { x: area.x + area.width - size - 24, y: area.y + area.height - size - 24 };
    }, 164);
    assert.deepEqual(placed, expected);
    await capture(settings, 'settings.png', false);
    results.push('Settings applied direct launch, hover multiplier, theme cycling and persisted bottom-right placement.');
    updated.expandsFacesOnClick = true;
    updated.themeCycle.isEnabled = false;
    await settings.evaluate(config => window.tcube.applyConfiguration(config), updated);
    await settings.evaluate(() => window.tcube.place('center'));
    await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows().find(win => win.webContents.getURL().endsWith('/settings.html'))?.hide());
    const centered = await bounds();
    await move(centered.x + centered.width / 2, centered.y + centered.height / 2);
    await until(snapshot, value => value.state.hovered, 'Hover before expansion missing');
    const enlarged = await bounds();
    if (process.platform === 'win32') {
        input.button(0, true);
        await until(snapshot, value => value.state.interactionActive, 'Expansion click not received');
        input.button(0, false);
    } else await widget.mouse.click(enlarged.width / 2, enlarged.height / 2);
    const expanded = await until(async () => app!.windows(), pages => pages.some(page => page.url().endsWith('/expanded.html')), 'Expansion missing').then(pages => pages.find(page => page.url().endsWith('/expanded.html'))!);
    await until(() => expanded.locator('button').count(), count => count === 4, 'Expansion should contain exactly four icon buttons');
    await sendPreviewIcons();
    assert.equal((await expanded.locator('body').innerText()).trim(), '');
    await capture(expanded, 'expanded.png');
    await expanded.keyboard.press('Escape');
    await until(snapshot, value => value.state.expandedFace === null, 'Escape failed to close expansion');
    results.push('Four-icon expansion has no visible text/close control and Escape dismisses it.');
    assert.deepEqual(errors, []);
    results.push('No widget renderer exceptions.');
    console.log(results.join('\n'));
    await writeFile(path.join(output, 'results.json'), JSON.stringify({ platform: process.platform, results }, null, 2));
} catch (error) {
    await writeFile(path.join(output, 'failure.txt'), error instanceof Error ? error.stack ?? error.message : String(error));
    if (widget) await capture(widget, 'failure.png').catch(() => {});
    throw error;
} finally {
    if (process.platform === 'win32') { input.control(false); input.button(0, false); input.button(2, false); }
    if (originalCursor) await move(originalCursor.x, originalCursor.y).catch(() => {});
    await app?.close().catch(() => {});
    if (catalogRegistered) execFileSync('reg.exe', ['DELETE', catalogRegistryKey, '/f'], { windowsHide: true });
    await rm(data, { recursive: true, force: true });
}
