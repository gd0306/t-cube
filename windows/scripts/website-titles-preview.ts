import assert from 'node:assert/strict';
import { readFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { chromium } from 'playwright';
import { defaultConfiguration } from '../src/core/configuration.js';
import { assertExpandedWebsiteTitles, projectedWebsiteTitle, websiteTitle, websiteTitleFixture } from './website-titles-smoke.js';

const output = path.resolve('.cache/website-titles');
await mkdir(output, { recursive: true });
const browser = await chromium.launch({ channel: 'chrome', headless: true,
    args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const context = await browser.newContext({ viewport: { width: 440, height: 440 } });
const external: string[] = [], errors: string[] = [];
const config = websiteTitleFixture(defaultConfiguration());
try {
    // tsx may preserve names on functions serialized by Playwright. The shim is fixture-only.
    await context.addInitScript('window.__name = (value) => value;');
    await context.route('**/*', async route => {
        const url = new URL(route.request().url());
        if (url.origin !== 'http://tcube.test') { external.push(url.href); await route.abort(); return; }
        const filename = path.basename(url.pathname);
        try {
            const body = await readFile(path.resolve('dist/renderer', filename));
            await route.fulfill({ body, contentType: filename.endsWith('.js') ? 'text/javascript' : filename.endsWith('.css') ? 'text/css' : 'text/html' });
        } catch { await route.fulfill({ status: 404, body: '' }); }
    });
    await context.addInitScript(({ config }) => {
        const state = { configuration: config, displayedAppearance: config.appearance, activeTheme: null,
            hovered: true, pointer: null, controlHeld: false, interactionActive: false, rotationDrag: null,
            reducedMotion: true, visible: true, expandedFace: 'front', platform: 'win32' };
        const icon = 'data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect x="3" y="3" width="94" height="94" rx="24" fill="#4285ee"/><circle cx="50" cy="50" r="29" fill="none" stroke="white" stroke-width="6"/><path d="M20 50h60M50 20v60" stroke="white" stroke-width="5"/></svg>');
        const icons = Object.fromEntries(Object.values(config.groups).flatMap(group => group.slots.filter(Boolean).map(item => [item!.id, icon])));
        const callbacks: ((state: unknown) => void)[] = [];
        const host = { state, painted: [] as string[], gestures: [] as unknown[], launches: [] as unknown[], update: (edit: Record<string, unknown>) => {
            Object.assign(state, edit); callbacks.forEach(callback => callback(state));
        } };
        Object.assign(window, { __titleFixture: host });
        const fillText = CanvasRenderingContext2D.prototype.fillText;
        CanvasRenderingContext2D.prototype.fillText = function(text, ...args: [number, number, number?]) {
            host.painted.push(text); return fillText.call(this, text, ...args);
        };
        window.tcube = { getSnapshot: async () => ({ state, icons }), onState: (callback: (state: unknown) => void) => { callbacks.push(callback); return () => {}; },
            onIcons: () => () => {}, onError: () => () => {}, beginPointer: async () => 1,
            endPointer: async (request: unknown) => { host.gestures.push(request); },
            launch: async (request: unknown) => { host.launches.push(request); }, closeExpanded: async () => {} } as never;
    }, { config });
    const expanded = await context.newPage();
    expanded.on('pageerror', error => errors.push(error.message));
    await expanded.goto('http://tcube.test/expanded.html');
    assert.equal(errors.length, 0, `Expanded renderer must initialize without exceptions: ${JSON.stringify(errors)}`);
    await assertExpandedWebsiteTitles(expanded);
    await expanded.screenshot({ path: path.join(output, 'expanded.png') });
    await expanded.locator('button').first().locator('.website-title').click();
    assert.deepEqual(await expanded.evaluate(() => (window as any).__titleFixture.launches), [{ face: 'front', slot: 0 }]);
    const widget = await context.newPage();
    widget.on('pageerror', error => errors.push(error.message));
    await widget.goto('http://tcube.test/widget.html');
    await widget.waitForFunction(() => (window as any).__titleFixture.painted.some((text: string) => text.endsWith('…')));
    const painted = await widget.evaluate(() => (window as any).__titleFixture.painted as string[]);
    assert.ok(painted.every(text => text.endsWith('…') && text !== websiteTitle));
    const titlePoint = await widget.evaluate(async () => {
        const { controller } = await import(new URL('widget.js', location.href).href);
        const point = controller.camera.position.clone().set((283 / 1024 - 0.5) * 0.84, (0.5 - 495 / 1024) * 0.84, 0.5);
        point.multiplyScalar(0.5 / (point.x ** 4 + point.y ** 4 + point.z ** 4) ** 0.25);
        const normal = point.clone().set(point.x ** 3, point.y ** 3, point.z ** 3).normalize();
        point.addScaledVector(normal, 0.0015);
        controller.cube.updateMatrixWorld(true);
        point.applyMatrix4(controller.cube.matrixWorld).project(controller.camera);
        return { x: (point.x + 1) * innerWidth / 2, y: (1 - point.y) * innerHeight / 2 };
    });
    await widget.evaluate(point => {
        Object.assign(window, { __nativeOnlyPointerEvents: 0 });
        document.addEventListener('pointermove', () => { (window as any).__nativeOnlyPointerEvents++; });
        (window as any).__titleFixture.update({ hoverPointer: { x: point.x / innerWidth, y: point.y / innerHeight } });
    }, titlePoint);
    await widget.waitForFunction(name => document.querySelector('canvas')?.title === name, websiteTitle, { timeout: 2000 });
    assert.equal(await widget.locator('canvas').getAttribute('aria-label'), websiteTitle);
    assert.equal(await widget.evaluate(() => (window as any).__nativeOnlyPointerEvents), 0,
        'Native state alone must update the full caption without DOM pointermove');
    await widget.evaluate(() => { (window as any).__titleFixture.update({ hoverPointer: undefined }); });
    await widget.mouse.move(titlePoint.x, titlePoint.y);
    assert.equal(await widget.locator('canvas').getAttribute('title'), websiteTitle);
    assert.equal(await widget.locator('canvas').getAttribute('aria-label'), websiteTitle);
    await widget.evaluate(() => { (window as any).__titleFixture.update({ hoverPointer: null }); });
    await widget.waitForFunction(() => document.querySelector('canvas')?.title === '');
    assert.equal(await widget.locator('canvas').getAttribute('aria-label'), 'T-Cube',
        'An authoritative native exit must clear a stale DOM hover');
    const projected = await projectedWebsiteTitle(widget);
    await widget.evaluate(point => { (window as any).__titleFixture.update({ hoverPointer: {
        x: point.x / innerWidth, y: point.y / innerHeight,
    } }); }, projected);
    await widget.waitForFunction(name => document.querySelector('canvas')?.title === name, websiteTitle);
    await widget.evaluate(() => { (window as any).__titleFixture.update({ hoverPointer: undefined }); });
    await widget.mouse.click(titlePoint.x, titlePoint.y);
    assert.deepEqual(await widget.evaluate(() => (window as any).__titleFixture.gestures.at(-1).hit), { face: 'front', slot: null });
    await widget.evaluate(() => {
        const fixture = (window as any).__titleFixture;
        fixture.update({ configuration: { ...fixture.state.configuration, expandsFacesOnClick: false } });
    });
    await widget.mouse.click(titlePoint.x, titlePoint.y);
    assert.deepEqual(await widget.evaluate(() => (window as any).__titleFixture.gestures.at(-1).hit), { face: 'front', slot: 0 });
    await widget.evaluate(() => { document.body.style.background = '#18212e'; });
    await widget.screenshot({ path: path.join(output, 'widget.png') });
    await widget.evaluate(() => {
        const fixture = (window as any).__titleFixture;
        const configuration = structuredClone(fixture.state.configuration);
        configuration.groups.front.slots[0].name = '新入口';
        fixture.update({ configuration });
    });
    await widget.waitForFunction(() => (window as any).__titleFixture.painted.includes('新入口'));
    await widget.waitForFunction(() => document.querySelector('canvas')?.title === '新入口');
    await widget.evaluate(() => {
        const fixture = (window as any).__titleFixture;
        const configuration = structuredClone(fixture.state.configuration);
        configuration.groups.front.slots[0].kind = 'application';
        fixture.update({ configuration });
    });
    await widget.waitForFunction(() => document.querySelector('canvas')?.title === '');
    const captionAlpha = await widget.evaluate(async () => {
        const { controller } = await import(new URL('widget.js', location.href).href);
        const face = controller.cube.children.find((mesh: any) => mesh.geometry?.getAttribute('position').count === 1089);
        return face.material.map.image.data[(495 * 1024 + 283) * 4 + 3];
    });
    assert.equal(captionAlpha, 0, 'Changing the target kind must remove the caption pixels');
    assert.deepEqual(external, []);
    assert.deepEqual(errors, []);
    console.log('Website title renderer preview passed: native-state-only full tooltip/accessibility without DOM pointermove; native exit precedence and projected title point; expanded truncation/activation; click modes, rename repaint, kind removal, and atlas ellipsis. No external requests.');
} finally { await context.close(); await browser.close(); }
