import assert from 'node:assert/strict';
import { mkdir, mkdtemp, writeFile, rm, copyFile, realpath } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import os from 'node:os';
import path from 'node:path';
import { _electron, type ElectronApplication, type Page } from 'playwright';
import { defaultConfiguration } from '../src/core/configuration.js';
import { FACES, type Configuration } from '../src/shared/contracts.js';
import { nativeInput } from './native-input.js';
import { verifyAppearanceControls } from './appearance-controls.js';
import { verifyLibrarySmoke } from './office-library-smoke.js';

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
let originalAnimations: boolean | undefined;
let failed = false;
const input = nativeInput();
let previewIcons: Record<string, string> | undefined;
const catalogExecutable = path.join(data, 'catalog-smoke.exe');
const catalogRegistryKey = `HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\tcube-${path.basename(data)}.exe`;
let catalogRegistered = false;
const catalogDisplayName = `T-Cube catalog smoke ${path.basename(data)}`;
const catalogShortcut = process.platform === 'win32' ? path.join(process.env.APPDATA!, 'Microsoft', 'Windows', 'Start Menu', 'Programs', `${catalogDisplayName}.lnk`) : '';
let catalogShortcutCreated = false;
async function sendPreviewIcons() {
    if (!previewIcons) return;
    await app!.evaluate(({ BrowserWindow }, icons) => {
        for (const window of BrowserWindow.getAllWindows()) window.webContents.send('tcube:icons', icons);
    }, previewIcons);
}

async function until<T>(read: () => Promise<T>, check: (value: T) => boolean, message: string, timeout = 10_000): Promise<T> {
    const deadline = Date.now() + timeout;
    let last: T;
    do {
        last = await read();
        if (check(last)) return last;
        await new Promise(resolve => setTimeout(resolve, 50));
    } while (Date.now() < deadline);
    const detail = JSON.stringify(last!, (key, value) => key === 'icons' ? '[icon data omitted]' : value);
    throw new Error(`${message}: ${detail?.slice(0, 4000)}`);
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
    try {
        if (backdrop) await page.evaluate(async value => {
            document.body.style.background = value;
            await Promise.race([new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))), new Promise<void>(resolve => setTimeout(resolve, 250))]);
        }, background);
        // Capture the actual Electron surface. Playwright's screenshot preparation can
        // stall on the inactive transparent widget when Windows animations are enabled.
        const png = await app!.evaluate(async ({ BrowserWindow }, url) => {
            const window = BrowserWindow.getAllWindows().find(win => win.webContents.getURL() === url);
            if (!window) throw new Error(`Capture window missing: ${url}`);
            return (await window.webContents.capturePage()).toPNG().toString('base64');
        }, page.url());
        await writeFile(path.join(output, name), Buffer.from(png, 'base64'));
    } finally {
        await page.evaluate(value => { document.body.style.background = value; }, previous);
    }
}

try {
    if (process.platform === 'win32') {
        await copyFile(path.join(process.env.WINDIR!, 'System32', 'notepad.exe'), catalogExecutable);
        execFileSync('reg.exe', ['ADD', catalogRegistryKey, '/ve', '/t', 'REG_SZ', '/d', catalogExecutable, '/f'], { windowsHide: true });
        catalogRegistered = true;
        execFileSync('reg.exe', ['ADD', catalogRegistryKey, '/v', 'FriendlyAppName', '/t', 'REG_SZ', '/d', catalogDisplayName, '/f'], { windowsHide: true });
    }
    const executablePath = process.env.TCUBE_SMOKE_EXECUTABLE;
    app = await _electron.launch({
        executablePath,
        args: [...(executablePath ? [] : [path.resolve('.')]), ...(process.platform === 'win32' ? ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] : [])],
        env: { ...process.env, TCUBE_USER_DATA_DIR: data },
        timeout: 30_000
    });
    originalCursor = await app.evaluate(({ screen }) => screen.getCursorScreenPoint());
    if (process.platform === 'win32') {
        await mkdir(path.dirname(catalogShortcut), { recursive: true });
        catalogShortcutCreated = await app.evaluate(({ shell }, fixture) => shell.writeShortcutLink(fixture.link, 'create', {
            target: fixture.executable, cwd: fixture.directory, description: fixture.name, appUserModelId: fixture.id,
        }), { link: catalogShortcut, executable: catalogExecutable, directory: data, name: catalogDisplayName, id: `TCube.Smoke.${path.basename(data)}` });
        assert.ok(catalogShortcutCreated);
    }
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
    await until(() => widget.evaluate(async () => {
        const { controller } = await import(new URL('widget.js', location.href).href);
        return controller.cube.children.filter((mesh: any) => mesh.geometry?.getAttribute('position').count === 1089)
            .every((mesh: any) => mesh.material.opacity === 0);
    }), Boolean, 'Launcher icons must be hidden at rest, matching macOS');
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
    assert.ok(contour.light >= 0.015, 'Glass contour is effectively invisible over a light desktop');
    assert.ok(contour.centerAlpha < 0.18, 'The glass center should remain transparent');
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
    await until(() => widget.evaluate(async () => {
        const { controller } = await import(new URL('widget.js', location.href).href);
        return controller.cube.children.filter((mesh: any) => mesh.geometry?.getAttribute('position').count === 1089)
            .every((mesh: any) => mesh.material.opacity === 1);
    }), Boolean, 'Hover must reveal launcher icons');
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
        await until(snapshot, value => JSON.stringify(value.state.configuration.windowPosition) !== JSON.stringify(configuration.windowPosition), 'Ctrl drag did not persist its new position');
        results.push('Inactive-window Ctrl shrink, Ctrl-left drag, Ctrl release mid-drag and native mouse-up persisted position.');
    } else results.push('Native Windows Ctrl/button paths skipped on macOS preview.');

    if (process.platform === 'win32') {
        const pose = () => widget.evaluate(async () => {
            const { controller } = await import(new URL('widget.js', location.href).href);
            return controller.cube.quaternion.toArray() as number[];
        });
        const changed = (a: number[], b: number[]) => Math.abs(a.reduce((sum, value, i) => sum + value * b[i], 0)) < 0.99;
        const resting = await bounds();
        await move(resting.x + resting.width / 2, resting.y + resting.height / 2);
        await until(bounds, frame => frame.width === 656, 'Right-drag hover did not enlarge');
        const before = await bounds();
        const saved = (await snapshot()).state.configuration.windowPosition;
        const initialPose = await pose();
        input.button(2, true);
        await until(snapshot, value => value.state.interactionActive, 'Right rotation did not begin');
        await move(before.x + before.width / 2 + 100, before.y + before.height / 2);
        await until(pose, value => changed(value, initialPose), 'Horizontal right drag did not rotate');
        const horizontalPose = await pose();
        await move(before.x + before.width + 100, before.y + before.height + 100);
        await until(pose, value => changed(value, horizontalPose), 'Outside vertical right drag did not rotate');
        assert.deepEqual(await bounds(), before, 'Right dragging must not move the window');
        input.button(2, false);
        await until(snapshot, value => !value.state.interactionActive, 'Right rotation release was lost');
        const stopped = await pose();
        await new Promise(resolve => setTimeout(resolve, 200));
        assert.ok(!changed(await pose(), stopped), 'Released rotation must not snap');
        assert.deepEqual((await snapshot()).state.configuration.windowPosition, saved, 'Right rotation must not save a new position');
        await move(2, 2);
        await until(bounds, frame => frame.width === 164, 'Right-drag exit did not shrink');
        const leftResting = await bounds();
        await move(leftResting.x + 82, leftResting.y + 82);
        await until(bounds, frame => frame.width === 656, 'Left-drag hover did not enlarge');
        const leftBefore = await bounds();
        const leftPose = await pose();
        input.button(0, true);
        await until(snapshot, value => value.state.interactionActive, 'Left move did not begin');
        await move(leftBefore.x + leftBefore.width / 2 + 120, leftBefore.y + leftBefore.height / 2 + 60);
        await until(bounds, frame => frame.x > leftBefore.x + 100 && frame.y > leftBefore.y + 40, 'Left drag did not move the window');
        assert.ok(!changed(await pose(), leftPose), 'Left move must not rotate');
        input.button(0, false);
        await until(snapshot, value => !value.state.interactionActive, 'Left move release was lost');
        await until(snapshot, value => JSON.stringify(value.state.configuration.windowPosition) !== JSON.stringify(saved), 'Left move did not persist position');
        assert.equal((await snapshot()).state.expandedFace, null, 'A drag must not expand a face');
        await move(2, 2);
        results.push('Native left drag moved and saved; right drag rotated both axes outside widget bounds without moving, saving or snapping.');
    }

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
        // The real discovery subprocess has a 20-second bound, plus UI delivery.
        await until(() => settings.locator('.application-result').count(), count => count > 1, 'Installed application list is empty', 30_000);
        await settings.locator('.application-icon img').first().waitFor({ state: 'visible', timeout: 10_000 });
        await capture(settings, 'application-picker-all.png', false);
        await search.fill('T-Cube catalog smoke');
        await settings.getByRole('button', { name: '刷新列表', exact: true }).click();
        await until(() => settings.getByRole('button', { name: '刷新列表', exact: true }).isEnabled(), Boolean, 'Application refresh did not finish', 30_000);
        const result = settings.locator('.application-result').filter({ hasText: 'T-Cube catalog smoke' }).first();
        await result.waitFor({ state: 'visible', timeout: 30_000 });
        assert.equal(await settings.locator('.application-result').filter({ hasText: 'T-Cube catalog smoke' }).count(), 1, 'Short paths and shortcut aliases should appear as one application');
        await capture(settings, 'application-picker.png', false);
        await result.click();
        await settings.locator('.application-picker').waitFor({ state: 'hidden' });
        const expectedShortcut = await realpath(catalogShortcut);
        await until(async () => {
            const file = (await snapshot()).state.configuration.groups.right.slots[0]?.path;
            return file && /\.lnk$/i.test(file) ? realpath(file).catch(() => '') : '';
        }, value => value === expectedShortcut, 'Catalog selection did not preserve the original launch shortcut');
        assert.equal((await snapshot()).state.configuration.groups.right.slots[0]?.name, catalogDisplayName);
        const originalLink = await app.evaluate(({ shell }, file) => shell.readShortcutLink(file), catalogShortcut);
        assert.equal(await realpath(originalLink.cwd!), await realpath(data));
        assert.equal(originalLink.args ?? '', '');
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
    await settings.getByRole('button', { name: '外观与主题', exact: true }).click();
    if (process.platform === 'win32') {
        const before = (await snapshot()).state.configuration;
        await verifyAppearanceControls(settings);
        await settings.evaluate(config => window.tcube.applyConfiguration(config), before);
        await until(() => settings.getByRole('combobox', { name: '材质', exact: true }).inputValue(), value => value === 'glass', 'Material control did not restore after menu checks');
        results.push('Real click-open and keyboard selection persisted both material and optical-style choices without replacing native menus.');
    }
    const materialControl = settings.getByRole('combobox', { name: '材质', exact: true });
    assert.equal(await materialControl.inputValue(), 'glass');
    const readShell = () => widget.evaluate(async () => {
        const { controller } = await import(new URL('widget.js', location.href).href);
        const shell: any = controller.cube.getObjectByName('glass-shell');
        return Array.from(shell.geometry.getAttribute('position').array) as number[];
    });
    const rigidShell = await readShell();
    const iconsBefore = await widget.evaluate(async () => {
        const { controller } = await import(new URL('widget.js', location.href).href);
        return controller.cube.children.filter((mesh: any) => mesh.geometry?.getAttribute('position').count === 1089)
            .map((mesh: any) => [mesh.geometry.uuid, mesh.geometry.getAttribute('position').version]);
    });
    await materialControl.selectOption('slime');
    await until(snapshot, value => value.state.configuration.appearance.material === 'slime', 'Material selector did not persist slime');
    await settings.getByRole('button', { name: '海洋', exact: true }).click();
    await until(snapshot, value => value.state.configuration.appearance.primaryHex === '#4CB8FF', 'Shared theme did not apply');
    assert.equal((await snapshot()).state.displayedAppearance.material, 'slime', 'Selecting a theme must preserve material');
    const cycling = structuredClone((await snapshot()).state.configuration);
    cycling.themeCycle = { isEnabled: true, themes: ['ocean', 'sunset'], intervalSeconds: 10 };
    await settings.evaluate(config => window.tcube.applyConfiguration(config), cycling);
    await until(snapshot, value => value.state.activeTheme === 'ocean', 'Theme cycling did not start');
    assert.equal((await snapshot()).state.displayedAppearance.material, 'slime');
    await capture(settings, 'settings-materials.png', false);
    await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows().find(win => win.webContents.getURL().endsWith('/settings.html'))?.hide());
    if (process.platform === 'win32') {
        originalAnimations = input.animations();
        input.animations(true);
        assert.equal(input.animations(), true);
        await until(snapshot, value => !value.state.reducedMotion, 'Native animation preference did not enable slime motion');
    }
    const slimeResting = await bounds();
    await move(slimeResting.x + slimeResting.width / 2, slimeResting.y + slimeResting.height / 2);
    await until(bounds, frame => frame.width > 300, 'Slime hover enlargement failed');
    const slimeFrame = await bounds();
    await move(slimeFrame.x + slimeFrame.width / 2, slimeFrame.y + slimeFrame.height / 2);
    console.log('Slime native input:', JSON.stringify(await widget.evaluate(async () => {
        const { state } = await window.tcube.getSnapshot();
        return { pointer: state.pointer, hovered: state.hovered, interactionActive: state.interactionActive,
            reducedMotion: state.reducedMotion, material: state.displayedAppearance.material,
            innerWidth, innerHeight, screenX, screenY, hidden: document.hidden };
    })));
    const shellDistance = () => widget.evaluate(async (original: number[]) => {
        const { controller } = await import(new URL('widget.js', location.href).href);
        const shell: any = controller.cube.getObjectByName('glass-shell');
        const points = shell.geometry.getAttribute('position').array;
        let largest = 0;
        for (let i = 0; i < points.length; i += 3) largest = Math.max(largest,
            Math.hypot(points[i] - original[i], points[i + 1] - original[i + 1], points[i + 2] - original[i + 2]));
        return largest;
    }, rigidShell);
    await until(shellDistance, value => value > 0.04, 'Actual native pointer motion did not deform the slime shell');
    if (process.platform === 'win32') {
        input.animations(false);
        await until(snapshot, value => value.state.reducedMotion, 'Native reduced-motion setting was not observed');
        await until(shellDistance, value => value < 0.0001, 'Reduced Motion must restore an undeformed shell');
        input.animations(true);
        await until(snapshot, value => !value.state.reducedMotion, 'Native animation preference did not resume');
        await until(shellDistance, value => value > 0.04, 'Slime did not resume under the stationary native pointer');
        results.push('Actual Windows animation preference disabled deformation and restoring it resumed native pointer response.');
    }
    const iconsAfter = await widget.evaluate(async () => {
        const { controller } = await import(new URL('widget.js', location.href).href);
        return controller.cube.children.filter((mesh: any) => mesh.geometry?.getAttribute('position').count === 1089)
            .map((mesh: any) => [mesh.geometry.uuid, mesh.geometry.getAttribute('position').version]);
    });
    assert.deepEqual(iconsAfter, iconsBefore, 'Slime must not deform launcher decals');
    await capture(widget, 'widget-slime-hover.png');
    await capture(widget, 'widget-slime-hover-light.png', true, '#f5f6f8');
    await move(2, 2);
    await until(shellDistance, value => value < 0.0001, 'Slime did not settle after native pointer exit');
    await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows().find(win => win.webContents.getURL().endsWith('/settings.html'))?.show());
    await materialControl.selectOption('glass');
    await until(snapshot, value => value.state.displayedAppearance.material === 'glass', 'Glass selection failed during cycling');
    assert.deepEqual(await readShell(), rigidShell, 'Glass must restore the original rigid geometry');
    results.push('Independent material UI, shared theme/cycling, native slime pointer deformation, stable icon decals, rebound and glass restoration passed.');

    results.push(...await verifyLibrarySmoke(app, widget));
    await move(2, 2);
    const idleConfiguration = structuredClone((await snapshot()).state.configuration);
    idleConfiguration.themeCycle.isEnabled = false;
    idleConfiguration.autoRotatesWhenIdle = true;
    await settings.evaluate(config => window.tcube.applyConfiguration(config), idleConfiguration);
    await settings.evaluate(() => window.tcube.setPerformanceSettings(true));
    const metrics = () => widget.evaluate(async () => {
        const { controller } = await import(new URL('widget.js', location.href).href);
        return {...controller.metrics};
    });
    await until(metrics, value => value.cadence === 0, 'Office idle must stop its animation timer');
    const idleFrames = (await metrics()).frames;
    await new Promise(resolve => setTimeout(resolve, 500));
    assert.equal((await metrics()).frames, idleFrames, 'Office idle must not keep rendering frames');
    if (process.platform === 'win32') {
        await settings.evaluate(() => window.tcube.setPerformanceSettings(false));
        await until(metrics, value => value.cadence === 15, 'Continuous display must use 15Hz idle animation');
        const continuousFrames = (await metrics()).frames;
        await until(metrics, value => value.frames > continuousFrames + 2, 'Continuous animation did not resume');
        await settings.evaluate(() => window.tcube.setPerformanceSettings(true));
        await until(metrics, value => value.cadence === 0, 'Returning to office mode must stop rendering');
    }
    await settings.evaluate(config => window.tcube.applyConfiguration(config), {...idleConfiguration, autoRotatesWhenIdle: false});
    const beforeBackup = await snapshot();
    await settings.evaluate(() => window.tcube.createBackup());
    const maintenance = await settings.evaluate(() => window.tcube.getMaintenanceState());
    assert.ok(maintenance.backups.length > 0, 'Manual backup missing');
    await settings.evaluate(() => window.tcube.renameGroup({face:'front',name:'Temporary backup probe'}));
    const preview = await settings.evaluate(id => window.tcube.previewImportBackup(id), maintenance.backups[0].id);
    assert.ok(preview);
    await settings.evaluate(token => window.tcube.confirmImportBackup(token), preview.token);
    await until(snapshot, value => value.state.configuration.groups.front.name === beforeBackup.state.configuration.groups.front.name, 'Backup did not restore current host state');
    const lifecycle = await settings.evaluate(() => window.tcube.getLifecycleState());
    assert.equal(lifecycle.version, '0.16.0');
    assert.equal(lifecycle.updatesEnabled, false, 'Unsigned CI installers must not enable automatic replacement');
    results.push('Default office mode stops frame rendering; continuous mode resumes at 15Hz; backup preview/restore and unsigned updater gate passed.');

    const saved = await snapshot();
    const updated = structuredClone(saved.state.configuration);
    updated.expandsFacesOnClick = false;
    updated.hover.multiplier = 2;
    updated.themeCycle = { isEnabled: true, themes: ['ocean', 'sunset'], intervalSeconds: 10 };
    await settings.evaluate(config => window.tcube.applyConfiguration(config), updated);
    await until(snapshot, value => !value.state.configuration.expandsFacesOnClick
        && (value.state.activeTheme === 'ocean' || value.state.activeTheme === 'sunset'), 'Preference change not applied');
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
    failed = true;
    await writeFile(path.join(output, 'failure.txt'), error instanceof Error ? error.stack ?? error.message : String(error));
    if (widget) await capture(widget, 'failure.png').catch(() => {});
    throw error;
} finally {
    const cleanupErrors: unknown[] = [];
    const clean = async (action: () => unknown) => {
        try { await action(); } catch (error) { cleanupErrors.push(error); }
    };
    if (process.platform === 'win32') {
        await clean(() => input.control(false));
        await clean(() => input.button(0, false));
        await clean(() => input.button(2, false));
        if (originalAnimations !== undefined) await clean(() => input.animations(originalAnimations));
    }
    if (originalCursor) await clean(() => move(originalCursor!.x, originalCursor!.y));
    await clean(async () => {
        if (!app) return;
        let timeout: ReturnType<typeof setTimeout> | undefined;
        try {
            await Promise.race([app.close(), new Promise<never>((_resolve,reject) => {
                timeout=setTimeout(() => reject(new Error('Owned smoke application did not finish quitting within 15 seconds')),15000);
            })]);
        } catch (error) {
            await writeFile(path.join(output,'quit-failure.txt'),String(error));
            app.process().kill();
            throw error;
        } finally { if(timeout)clearTimeout(timeout); }
    });
    if (catalogShortcutCreated) await clean(() => rm(catalogShortcut, { force: true }));
    if (catalogRegistered) await clean(() => execFileSync('reg.exe', ['DELETE', catalogRegistryKey, '/f'], { windowsHide: true }));
    await clean(() => rm(data, { recursive: true, force: true }));
    if (cleanupErrors.length) {
        const error = new AggregateError(cleanupErrors, 'Smoke fixture cleanup failed');
        if (failed) console.error(error);
        else throw error;
    }
}
