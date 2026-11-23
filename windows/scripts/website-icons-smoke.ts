import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { _electron, type ElectronApplication } from 'playwright';
import { defaultConfiguration } from '../src/core/configuration';
import { FACES } from '../src/shared/contracts';

// Real PNG and a classic 32-bit DIB ICO exercise Electron's production pixel decoder.
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGOQq7jzHwAEnAJy8OqzJgAAAABJRU5ErkJggg==', 'base64');
const dib = Buffer.alloc(40 + 16 * 16 * 4 + 16 * 4);
dib.writeUInt32LE(40, 0); dib.writeInt32LE(16, 4); dib.writeInt32LE(32, 8); dib.writeUInt16LE(1, 12); dib.writeUInt16LE(32, 14);
for (let pixel = 40; pixel < 40 + 16 * 16 * 4; pixel += 4) dib.set([220, 100, 40, 255], pixel);
const ico = Buffer.alloc(22 + dib.length);
ico.writeUInt16LE(1, 2); ico.writeUInt16LE(1, 4); ico[6] = ico[7] = 16;
ico.writeUInt16LE(1, 10); ico.writeUInt16LE(32, 12); ico.writeUInt32LE(dib.length, 14); ico.writeUInt32LE(22, 18); dib.copy(ico, 22);
const requests: string[] = [];
const servers = await Promise.all([png, ico, Buffer.from('<html>not an image</html>')].map(async (body, index) => {
    const server = createServer((request, response) => {
        requests.push(`${index}${request.url}`);
        if (request.url === '/favicon.ico') response.end(body);
        else { response.writeHead(404); response.end(); }
    });
    server.listen(0, '127.0.0.1'); await once(server, 'listening');
    const address = server.address(); assert.ok(address && typeof address !== 'string');
    return { server, origin: `http://127.0.0.1:${address.port}` };
}));
const data = await mkdtemp(path.join(os.tmpdir(), 'tcube-website-icons-'));
const output = path.resolve('.cache/smoke/website-icons'); await mkdir(output, { recursive: true });
const config = defaultConfiguration();
config.autoRotatesWhenIdle = false; config.themeCycle.isEnabled = false; config.scale = 1.6;
config.windowPosition = { x: 200, y: 150 }; config.hover.isEnabled = false;
const names = ['文档入口与网站图标 — Documentation', 'ICO 网站图标', '缺失图标回退'];
const live = process.argv.includes('--live');
for (const face of FACES) config.groups[face].slots = [
    ...[0, 1, 2].map(index => ({ id: `${face}-${index}`, kind: 'website' as const, name: names[index], path: `${servers[index].origin}/${face}` })),
    live ? { id: `${face}-live`, kind: 'website', name: 'T-Cube 官网', path: `https://tcube.gd306.cn/#${face}` } : null,
] as typeof config.groups.front.slots;
const file = path.join(data, 'configuration.json'); await writeFile(file, JSON.stringify(config));
let app: ElectronApplication | undefined;
try {
    app = await _electron.launch({ args: ['.'], env: { ...process.env, TCUBE_USER_DATA_DIR: data } });
    const formats = await app.evaluate(({ nativeImage }, bytes) => ({ png: nativeImage.createFromBuffer(Buffer.from(bytes.png, 'base64')).getSize(), ico: nativeImage.createFromBuffer(Buffer.from(bytes.ico, 'base64')).getSize(), svg: nativeImage.createFromBuffer(Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><circle cx="16" cy="16" r="10"/></svg>')).getSize() }), { png: png.toString('base64'), ico: ico.toString('base64') });
    console.log('Native image formats:', formats);
    let widget = app.windows().find(page => page.url().endsWith('/widget.html'));
    const windowDeadline = Date.now() + 10000;
    while (!widget && Date.now() < windowDeadline) {
        await new Promise(resolve => setTimeout(resolve, 50));
        widget = app.windows().find(page => page.url().endsWith('/widget.html'));
    }
    assert.ok(widget, 'Production widget must load');
    await widget.waitForLoadState('domcontentloaded');
    const deadline = Date.now() + (live ? 18000 : 8000);
    let icons: Record<string, string> = {};
    do {
        icons = (await widget.evaluate(() => window.tcube.getSnapshot())).icons;
        if (icons['front-0']?.startsWith('data:image/png;') && icons['front-1']?.startsWith('data:image/png;') && (!live || icons['front-live']?.startsWith('data:image/png;'))) break;
        await new Promise(resolve => setTimeout(resolve, 50));
    } while (Date.now() < deadline);
    assert.match(icons['front-0'] ?? '', /^data:image\/png;base64,/, 'Real PNG must decode through the production cache');
    assert.match(icons['front-1'] ?? '', /^data:image\/png;base64,/, 'Classic ICO must decode through the production cache');
    if (live) assert.match(icons['front-live'] ?? '', /^data:image\/png;base64,/, 'Public website homepage icon must load through production discovery');
    assert.match(icons['front-2'] ?? '', /^data:image\/svg\+xml/, 'HTML disguised as an icon retains the bundled fallback');
    assert.deepEqual(requests.sort(), ['0/favicon.ico', '1/favicon.ico', '2/', '2/favicon.ico'].sort(), 'Each origin is requested once, shared across all six faces');
    const pngSizes = await app.evaluate(({ nativeImage }, icons) => ['front-0', 'front-1'].map(id => nativeImage.createFromDataURL(icons[id]).getSize()), icons);
    assert.deepEqual(pngSizes, [{ width: 1, height: 1 }, { width: 16, height: 16 }]);
    const expandedPromise = app.waitForEvent('window');
    await app.evaluate(({ BrowserWindow }, files) => {
        new BrowserWindow({ width: 420, height: 420, webPreferences: { preload: files.preload, sandbox: true, contextIsolation: true, nodeIntegration: false } }).loadFile(files.expanded);
    }, { preload: path.resolve('dist/preload.cjs'), expanded: path.resolve('dist/renderer/expanded.html') });
    const expanded = await expandedPromise; await expanded.waitForLoadState('domcontentloaded');
    // The owned preview receives the actual host snapshot with an expanded face; no launcher is activated.
    const snapshot = await widget.evaluate(() => window.tcube.getSnapshot());
    snapshot.state.expandedFace = 'front'; snapshot.state.hovered = true;
    await app.evaluate(({ BrowserWindow }, snapshot) => {
        for (const win of BrowserWindow.getAllWindows()) if (['/expanded.html', '/widget.html'].some(suffix => win.webContents.getURL().endsWith(suffix))) {
            win.webContents.send('tcube:state', snapshot.state); win.webContents.send('tcube:icons', snapshot.icons);
        }
    }, snapshot);
    await expanded.locator('.website-name').first().getByText(names[0], { exact: true }).waitFor();
    const caption = await expanded.locator('button').first().evaluate(button => {
        const mark = button.querySelector<HTMLCanvasElement>('.website-globe')!;
        const pixels = mark.getContext('2d')!.getImageData(0, 0, mark.width, mark.height).data;
        let visible = 0;
        for (let index = 0; index < pixels.length; index += 4) if (pixels[index + 3]) {
            if (pixels[index] !== pixels[index + 1] || pixels[index + 1] !== pixels[index + 2]) throw Error('Colored globe pixel');
            visible++;
        }
        return { text: button.textContent, title: button.getAttribute('title'), accessible: button.getAttribute('aria-label'), visible, ellipsis: getComputedStyle(button.querySelector('.website-name')!).textOverflow };
    });
    assert.equal(caption.text, names[0]); assert.equal(caption.title, names[0]); assert.equal(caption.accessible, names[0]);
    assert.ok(caption.visible > 30); assert.equal(caption.ellipsis, 'ellipsis');
    await widget.waitForFunction(() => document.body.dataset.hovered === 'true');
    await widget.evaluate(async () => { const { controller } = await import(new URL('widget.js', location.href).href); controller.render(); });
    await widget.screenshot({ path: path.join(output, 'widget.png') });
    await expanded.screenshot({ path: path.join(output, 'expanded.png') });
    assert.deepEqual(JSON.parse(await readFile(file, 'utf8')), config, 'Image loading and decorative marks must not alter configuration');
    console.log('PASS: production favicon PNG/ICO decoding, same-origin sharing, HTML fallback, unchanged configuration and monochrome expanded captions.' + (live ? ' Public tcube.gd306.cn discovery also passed.' : ''));
} finally {
    if (app) {
        app.process().kill('SIGKILL');
    }
    for (const { server } of servers) { server.closeAllConnections(); await new Promise<void>(resolve => server.close(() => resolve())); }
    await rm(data, { recursive: true, force: true });
}
