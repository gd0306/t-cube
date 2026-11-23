/** Website requests use Node fetch, never an Electron/browser session or third-party service. */
export function websiteOrigin(target: string): string | null {
    try { return safeURL(target).origin; } catch { return null; }
}

function safeURL(target: string, base?: string, secure = false): URL {
    const url = new URL(target, base);
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || (secure && url.protocol !== 'https:')) throw Error('Unsafe website icon URL');
    url.hash = '';
    return url;
}

function validSize(width: number, height: number): boolean {
    return width > 0 && height > 0 && width <= 1024 && height <= 1024;
}

/** Header bounds precede native decoding; the decoder must still reject corrupt pixel data. */
export function isBoundedRaster(bytes: Buffer): boolean {
    if (bytes.length < 16 || bytes.length > 512 * 1024) return false;
    if (bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) {
        return bytes.length >= 33 && bytes.toString('ascii', 12, 16) === 'IHDR' && validSize(bytes.readUInt32BE(16), bytes.readUInt32BE(20));
    }
    if (bytes[0] === 0xff && bytes[1] === 0xd8) {
        let offset = 2;
        while (offset + 4 <= bytes.length) {
            if (bytes[offset++] !== 0xff) return false;
            while (bytes[offset] === 0xff) offset++;
            const marker = bytes[offset++];
            if (marker === 0xd9 || marker === 0xda || marker === undefined) return false;
            if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
            if (offset + 2 > bytes.length) return false;
            const length = bytes.readUInt16BE(offset);
            if (length < 2 || offset + length > bytes.length) return false;
            if ([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf].includes(marker)) {
                return length >= 8 && validSize(bytes.readUInt16BE(offset + 5), bytes.readUInt16BE(offset + 3));
            }
            offset += length;
        }
        return false;
    }
    if (bytes.readUInt32LE(0) === 0x00010000) {
        const count = bytes.readUInt16LE(4);
        if (!count || count > 64 || 6 + count * 16 > bytes.length) return false;
        for (let index = 0; index < count; index++) {
            const entry = 6 + index * 16, size = bytes.readUInt32LE(entry + 8), start = bytes.readUInt32LE(entry + 12);
            if (start < 6 + count * 16 || size < 16 || start + size > bytes.length) return false;
            const image = bytes.subarray(start, start + size);
            if (image[0] === 137) { if (!isBoundedRaster(image)) return false; }
            else if (image.length < 40 || image.readUInt32LE(0) < 40 || !validSize(image.readInt32LE(4), Math.abs(image.readInt32LE(8)) / 2)) return false;
        }
        return true;
    }
    if (bytes.toString('ascii', 0, 4) === 'RIFF' && bytes.toString('ascii', 8, 12) === 'WEBP' && bytes.length >= 30) {
        const kind = bytes.toString('ascii', 12, 16);
        if (kind === 'VP8X') return validSize(1 + bytes.readUIntLE(24, 3), 1 + bytes.readUIntLE(27, 3));
        if (kind === 'VP8 ' && bytes[23] === 0x9d && bytes[24] === 1 && bytes[25] === 0x2a) return validSize(bytes.readUInt16LE(26) & 0x3fff, bytes.readUInt16LE(28) & 0x3fff);
        if (kind === 'VP8L' && bytes[20] === 0x2f) {
            const bits = bytes.readUInt32LE(21);
            return validSize(1 + (bits & 0x3fff), 1 + ((bits >>> 14) & 0x3fff));
        }
    }
    return false;
}

/** Electron's buffer decoder accepts PNG/JPEG, so unpack ICO PNGs and classic uncompressed DIBs. */
export function decodeICO(bytes: Buffer): { png: Buffer } | { pixels: Buffer; width: number; height: number } | null {
    if (!isBoundedRaster(bytes) || bytes.readUInt32LE(0) !== 0x00010000) return null;
    let selected = 6, area = 0;
    for (let index = 0; index < bytes.readUInt16LE(4); index++) {
        const entry = 6 + index * 16, candidate = (bytes[entry] || 256) * (bytes[entry + 1] || 256);
        if (candidate > area) { area = candidate; selected = entry; }
    }
    const start = bytes.readUInt32LE(selected + 12), size = bytes.readUInt32LE(selected + 8);
    const image = bytes.subarray(start, start + size);
    if (image[0] === 137) return { png: image };
    const header = image.readUInt32LE(0), width = image.readInt32LE(4), height = Math.abs(image.readInt32LE(8)) / 2;
    const depth = image.readUInt16LE(14), colors = depth <= 8 ? (image.readUInt32LE(32) || (1 << depth)) : 0;
    if (header < 40 || header > image.length || !Number.isInteger(height) || !validSize(width, height)
        || image.readUInt16LE(12) !== 1 || ![1, 4, 8, 24, 32].includes(depth) || image.readUInt32LE(16) !== 0 || colors > 256) return null;
    const pixelStart = header + colors * 4, stride = Math.ceil(width * depth / 32) * 4;
    const maskStart = pixelStart + stride * height, maskStride = Math.ceil(width / 32) * 4;
    if (maskStart > image.length) return null;
    const hasMask = maskStart + maskStride * height <= image.length;
    let usesAlpha = false;
    if (depth === 32) for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
        if (image[pixelStart + y * stride + x * 4 + 3]) usesAlpha = true;
    }
    const pixels = Buffer.alloc(width * height * 4);
    for (let y = 0; y < height; y++) {
        const row = image.readInt32LE(8) > 0 ? height - 1 - y : y;
        for (let x = 0; x < width; x++) {
            const output = (y * width + x) * 4;
            let input = pixelStart + row * stride + x * (depth / 8);
            let alpha = depth === 32 && usesAlpha ? image[input + 3] : 255;
            if (hasMask && (image[maskStart + row * maskStride + (x >> 3)] & (0x80 >> (x & 7)))) alpha = 0;
            if (depth <= 8) {
                const packed = image[pixelStart + row * stride + Math.floor(x * depth / 8)];
                const palette = (packed >> (8 - depth - (x * depth % 8))) & ((1 << depth) - 1);
                if (palette >= colors) return null;
                input = header + palette * 4;
            }
            for (let channel = 0; channel < 3; channel++) pixels[output + channel] = Math.round(image[input + channel] * alpha / 255);
            pixels[output + 3] = alpha;
        }
    }
    return { pixels, width, height };
}

export type WebsiteIconDecoder = (bytes: Buffer) => Promise<string | null>;

/** Re-encode decoded pixels: no remote SVG or raw remote URL reaches the renderer. */
export const decodeWebsiteIcon: WebsiteIconDecoder = async bytes => {
    if (!isBoundedRaster(bytes)) return null;
    try {
        const { nativeImage } = await import('electron');
        const ico = bytes.readUInt32LE(0) === 0x00010000 ? decodeICO(bytes) : null;
        const image = ico && 'pixels' in ico
            ? nativeImage.createFromBitmap(ico.pixels, { width: ico.width, height: ico.height, scaleFactor: 1 })
            : nativeImage.createFromBuffer(ico && 'png' in ico ? ico.png : bytes);
        const { width, height } = image.getSize();
        if (image.isEmpty() || !validSize(width, height)) return null;
        const scale = Math.min(1, 128 / Math.max(width, height));
        const raster = scale < 1 ? image.resize({ width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale)) }) : image;
        return `data:image/png;base64,${raster.toPNG().toString('base64')}`;
    } catch { return null; }
};

function htmlAttribute(value: string): string {
    return value.replace(/&(?:amp|quot|apos|lt|gt|#\d+|#x[\da-f]+);/gi, entity => {
        const named: Record<string, string> = { '&amp;': '&', '&quot;': '"', '&apos;': "'", '&lt;': '<', '&gt;': '>' };
        if (named[entity.toLowerCase()]) return named[entity.toLowerCase()];
        const number = entity.toLowerCase().startsWith('&#x') ? parseInt(entity.slice(3, -1), 16) : parseInt(entity.slice(2, -1), 10);
        return number > 0 && number <= 0x10ffff ? String.fromCodePoint(number) : '';
    });
}

function iconLinks(html: string, base: string, secure: boolean): string[] {
    const candidates = new Set<string>();
    for (const match of html.replace(/<!--[\s\S]*?-->/g, '').matchAll(/<link\b[^>]*>/gi)) {
        const attributes = new Map<string, string>();
        for (const attribute of match[0].matchAll(/([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/g)) {
            attributes.set(attribute[1].toLowerCase(), htmlAttribute(attribute[2] ?? attribute[3] ?? attribute[4]));
        }
        const rel = (attributes.get('rel') ?? '').toLowerCase().split(/\s+/);
        if (!rel.some(value => ['icon', 'apple-touch-icon', 'apple-touch-icon-precomposed'].includes(value))) continue;
        if ((attributes.get('type') ?? '').toLowerCase().includes('svg')) continue;
        try {
            const url = safeURL(attributes.get('href') ?? '', base, secure);
            if (!attributes.get('href') || /\.svg$/i.test(url.pathname)) continue;
            candidates.add(url.href);
            if (candidates.size === 2) break;
        } catch { /* Ignore unsupported or credential-bearing candidates. */ }
    }
    return [...candidates];
}

export async function loadWebsiteIcon(target: string, decode: WebsiteIconDecoder = decodeWebsiteIcon,
    options: { signal?: AbortSignal; fetch?: typeof fetch } = {}): Promise<string | null> {
    const origin = websiteOrigin(target);
    if (!origin) return null;
    const secure = origin.startsWith('https:');
    const fetchResource = options.fetch ?? globalThis.fetch;
    let remaining = 4;
    const attempted = new Set<string>();
    async function request(targetURL: string, limit: number): Promise<{ bytes: Buffer; url: string } | null> {
        let current = targetURL;
        while (remaining > 0 && !options.signal?.aborted) {
            let url: URL;
            try { url = safeURL(current, undefined, secure); } catch { return null; }
            if (attempted.has(url.href)) return null;
            attempted.add(url.href); remaining--;
            const timeout = AbortSignal.timeout(4000);
            const signal = options.signal ? AbortSignal.any([timeout, options.signal]) : timeout;
            try {
                const response = await fetchResource(url.href, { redirect: 'manual', credentials: 'omit', referrerPolicy: 'no-referrer', signal });
                if ([301, 302, 303, 307, 308].includes(response.status)) {
                    await response.body?.cancel();
                    const location = response.headers.get('location');
                    if (!location) return null;
                    current = safeURL(location, url.href, secure || url.protocol === 'https:').href;
                    continue;
                }
                if (!response.ok || Number(response.headers.get('content-length')) > limit) { await response.body?.cancel(); return null; }
                const reader = response.body?.getReader();
                if (!reader) return null;
                const chunks: Buffer[] = []; let size = 0;
                try {
                    while (true) {
                        const { done, value } = await reader.read();
                        if (done) break;
                        size += value.length;
                        if (size > limit) { await reader.cancel(); return null; }
                        chunks.push(Buffer.from(value));
                    }
                } finally { reader.releaseLock(); }
                return { bytes: Buffer.concat(chunks, size), url: url.href };
            } catch { return null; }
        }
        return null;
    }
    async function icon(url: string): Promise<string | null> {
        const resource = await request(url, 512 * 1024);
        if (!resource || !isBoundedRaster(resource.bytes) || options.signal?.aborted) return null;
        try { return await decode(resource.bytes); } catch { return null; }
    }
    const conventional = await icon(`${origin}/favicon.ico`);
    if (conventional) return conventional;
    const homepage = await request(`${origin}/`, 256 * 1024);
    if (!homepage) return null;
    for (const candidate of iconLinks(homepage.bytes.toString('utf8'), homepage.url, secure || homepage.url.startsWith('https:'))) {
        const result = await icon(candidate);
        if (result) return result;
    }
    return null;
}
