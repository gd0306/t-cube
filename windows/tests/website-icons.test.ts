import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { once } from 'node:events';
import { defaultConfiguration } from '../src/core/configuration';
import { IconCache } from '../src/main/icons';

const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGOQq7jzHwAEnAJy8OqzJgAAAABJRU5ErkJggg==', 'base64');
const raster = `data:image/png;base64,${png.toString('base64')}`;
const turn = () => new Promise<void>(resolve => setImmediate(resolve));
const website = (id: string, path: string) => ({ id, name: '文档', kind: 'website' as const, path });

test('website cache returns fallback immediately then publishes one shared origin image without changing names', async () => {
    const config = defaultConfiguration();
    config.groups.front.slots[0] = website('a', 'https://example.com/a');
    config.groups.front.slots[1] = website('b', 'https://EXAMPLE.com/b');
    const original = structuredClone(config);
    let resolve!: (image: string | null) => void;
    const requested: string[] = [];
    let changed = 0;
    const cache = new IconCache({
        websiteIcon: async (origin: string) => { requested.push(origin); return new Promise<string | null>(done => { resolve = done; }); },
        onWebsiteIconChanged: () => { changed++; },
    });
    const initial = await cache.forConfiguration(config);
    assert.match(initial.a, /^data:image\/svg\+xml/);
    assert.deepEqual(requested, ['https://example.com']);
    assert.equal(initial.a, initial.b);
    resolve(raster); await turn();
    assert.equal(changed, 1);
    const loaded = await cache.forConfiguration(config);
    assert.equal(loaded.a, raster); assert.equal(loaded.b, raster);
    assert.equal(requested.length, 1); assert.deepEqual(config, original);
});

test('failed origins do not retry during refresh and removed origins are discarded', async () => {
    const config = defaultConfiguration();
    config.groups.front.slots[0] = website('a', 'https://example.com');
    let calls = 0, changed = 0;
    const cache = new IconCache({ websiteIcon: async () => { calls++; return null; }, onWebsiteIconChanged: () => { changed++; } });
    await cache.forConfiguration(config); await turn();
    for (let i = 0; i < 20; i++) assert.match((await cache.forConfiguration(config)).a, /^data:image\/svg\+xml/);
    assert.equal(calls, 1); assert.equal(changed, 0);
    config.groups.front.slots[0] = null; await cache.forConfiguration(config);
    config.groups.front.slots[0] = website('a', 'https://example.com'); await cache.forConfiguration(config); await turn();
    assert.equal(calls, 2);
});

test('a removed pending URL cannot publish an image for a replacement with the same id', async () => {
    const config = defaultConfiguration();
    config.groups.front.slots[0] = website('a', 'https://old.example');
    const pending = new Map<string, (image: string | null) => void>();
    let changed = 0;
    const cache = new IconCache({ websiteIcon: async (origin: string) => new Promise<string | null>(resolve => pending.set(origin, resolve)), onWebsiteIconChanged: () => { changed++; } });
    await cache.forConfiguration(config);
    config.groups.front.slots[0] = website('a', 'https://new.example');
    await cache.forConfiguration(config);
    pending.get('https://old.example')!(raster); await turn();
    assert.equal(changed, 0); assert.match((await cache.forConfiguration(config)).a, /^data:image\/svg\+xml/);
    pending.get('https://new.example')!(raster); await turn();
    assert.equal(changed, 1); assert.equal((await cache.forConfiguration(config)).a, raster);
});

async function fixture(handler: (request: IncomingMessage, response: ServerResponse) => void, run: (origin: string) => Promise<void>) {
    const server = createServer(handler); server.listen(0, '127.0.0.1'); await once(server, 'listening');
    const address = server.address(); assert.ok(address && typeof address !== 'string');
    try { await run(`http://127.0.0.1:${address.port}`); }
    finally { server.closeAllConnections(); await new Promise<void>(resolve => server.close(() => resolve())); }
}

test('favicon loader requests only the origin icon with no user URL path or ambient credentials', async () => {
    const { loadWebsiteIcon } = await import('../src/main/website-icons');
    const paths: string[] = [];
    await fixture((request, response) => {
        paths.push(request.url!);
        assert.equal(request.headers.cookie, undefined); assert.equal(request.headers.authorization, undefined); assert.equal(request.headers.referer, undefined);
        response.setHeader('content-type', 'image/png'); response.end(png);
    }, async origin => {
        const image = await loadWebsiteIcon(`${origin}/private/document?q=secret`, async bytes => { assert.deepEqual(bytes, png); return raster; });
        assert.equal(image, raster); assert.deepEqual(paths, ['/favicon.ico']);
    });
});

test('HTML fallback resolves icon links against the final homepage URL and skips remote SVGs', async () => {
    const { loadWebsiteIcon } = await import('../src/main/website-icons');
    const paths: string[] = [];
    await fixture((request, response) => {
        paths.push(request.url!);
        if (request.url === '/favicon.ico') { response.writeHead(404); response.end(); }
        else if (request.url === '/') { response.setHeader('content-type', 'text/html'); response.end('<link rel="icon" href="/vector.svg"><link href="/brand.png?v=1&amp;x=2" rel="shortcut icon">'); }
        else if (request.url === '/brand.png?v=1&x=2') { response.end(png); }
        else { response.writeHead(500); response.end(); }
    }, async origin => {
        assert.equal(await loadWebsiteIcon(`${origin}/some/page`, async () => raster), raster);
        assert.deepEqual(paths, ['/favicon.ico', '/', '/brand.png?v=1&x=2']);
    });
});

test('loader rejects HTML disguised as icons, oversized bodies and dimensions before decoding', async () => {
    const { loadWebsiteIcon } = await import('../src/main/website-icons');
    for (const body of [Buffer.from('<html>not an icon</html>'), Buffer.alloc(512 * 1024 + 1), (() => { const data = Buffer.from(png); data.writeUInt32BE(1025, 16); return data; })()]) {
        let decodes = 0;
        await fixture((request, response) => { if (request.url === '/favicon.ico') response.end(body); else { response.writeHead(404); response.end(); } }, async origin => {
            assert.equal(await loadWebsiteIcon(origin, async () => { decodes++; return raster; }), null);
            assert.equal(decodes, 0);
        });
    }
});

test('redirects consume the four request budget and invalid URLs are rejected without decoding', async () => {
    const { loadWebsiteIcon } = await import('../src/main/website-icons');
    let requests = 0;
    await fixture((_request, response) => { requests++; response.writeHead(302, { location: `/again-${requests}` }); response.end(); }, async origin => {
        assert.equal(await loadWebsiteIcon(origin, async () => raster), null); assert.equal(requests, 4);
    });
    let decodes = 0;
    for (const url of ['file:///tmp/icon', 'https://user:password@example.com', 'data:image/png;base64,AAAA']) {
        assert.equal(await loadWebsiteIcon(url, async () => { decodes++; return raster; }), null);
    }
    assert.equal(decodes, 0);
});

test('HTTPS redirects and advertised icons never downgrade or send URL credentials', async () => {
    const { loadWebsiteIcon } = await import('../src/main/website-icons');
    for (const location of ['http://example.test/unsafe.png', 'https://user:secret@example.test/unsafe.png', 'file:///tmp/icon']) {
        const requested: string[] = [];
        const fakeFetch: typeof fetch = async input => {
            requested.push(String(input));
            return new Response(null, { status: 302, headers: { location } });
        };
        assert.equal(await loadWebsiteIcon('https://example.test/path', async () => raster, { fetch: fakeFetch }), null);
        assert.deepEqual(requested, ['https://example.test/favicon.ico', 'https://example.test/']);
    }
});

test('HTML size, streamed icon size and failed native decoding all retain fallback', async () => {
    const { loadWebsiteIcon } = await import('../src/main/website-icons');
    let decodes = 0;
    await fixture((request, response) => {
        if (request.url === '/favicon.ico') { response.writeHead(404); response.end(); }
        else response.end(`<link rel="icon" href="/large.png">${' '.repeat(256 * 1024)}`);
    }, async origin => {
        assert.equal(await loadWebsiteIcon(origin, async () => { decodes++; return raster; }), null); assert.equal(decodes, 0);
    });
    await fixture((request, response) => {
        if (request.url === '/favicon.ico') {
            response.write(png); response.end(Buffer.alloc(512 * 1024));
        } else { response.writeHead(404); response.end(); }
    }, async origin => {
        assert.equal(await loadWebsiteIcon(origin, async () => { decodes++; return raster; }), null); assert.equal(decodes, 0);
    });
    await fixture((request, response) => {
        if (request.url === '/favicon.ico') response.end(png);
        else { response.writeHead(404); response.end(); }
    }, async origin => {
        assert.equal(await loadWebsiteIcon(origin, async () => null), null);
        assert.equal(await loadWebsiteIcon(origin, async () => { throw Error('corrupt pixels'); }), null);
    });
});

test('removing an origin aborts its pending request', async () => {
    const config = defaultConfiguration();
    config.groups.front.slots[0] = website('a', 'https://example.com');
    let signal: AbortSignal | undefined;
    const cache = new IconCache({ websiteIcon: async (_origin, pendingSignal) => { signal = pendingSignal; return new Promise(() => {}); } });
    await cache.forConfiguration(config);
    assert.equal(signal?.aborted, false);
    config.groups.front.slots[0] = null; await cache.forConfiguration(config);
    assert.equal(signal?.aborted, true);
});

test('an unresponsive response is bounded by the per-request deadline', async () => {
    const { loadWebsiteIcon } = await import('../src/main/website-icons');
    await fixture((request, response) => {
        if (request.url !== '/favicon.ico') { response.writeHead(404); response.end(); }
    }, async origin => {
        const start = Date.now();
        assert.equal(await loadWebsiteIcon(origin, async () => raster), null);
        assert.ok(Date.now() - start >= 3900 && Date.now() - start < 6000);
    });
});

test('classic ICO DIB pixels are flipped, alpha masked and converted for the native bitmap decoder', async () => {
    const { decodeICO } = await import('../src/main/website-icons');
    const bytes = Buffer.alloc(22 + 40 + 16 + 8);
    bytes.writeUInt16LE(1, 2); bytes.writeUInt16LE(1, 4); bytes[6] = bytes[7] = 2;
    bytes.writeUInt32LE(bytes.length - 22, 14); bytes.writeUInt32LE(22, 18);
    bytes.writeUInt32LE(40, 22); bytes.writeInt32LE(2, 26); bytes.writeInt32LE(4, 30);
    bytes.writeUInt16LE(1, 34); bytes.writeUInt16LE(32, 36);
    bytes.set([255, 0, 0, 0, 0, 255, 0, 0, 0, 0, 255, 0, 255, 255, 255, 0], 62);
    bytes[82] = 0x40; // Top-right pixel is transparent according to the top row of the AND mask.
    const decoded = decodeICO(bytes);
    assert.ok(decoded && 'pixels' in decoded);
    assert.equal(decoded.width, 2); assert.equal(decoded.height, 2);
    assert.deepEqual([...decoded.pixels], [0, 0, 255, 255, 0, 0, 0, 0, 255, 0, 0, 255, 0, 255, 0, 255]);
});
