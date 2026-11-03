import { CLIPBOARD_IMAGE_LIMITS as LIMITS } from '../shared/clipboard-history';
/** Inspect PNG dimensions before asking the native decoder to allocate bitmap storage. */
export function pngDimensions(png: Buffer): {width: number; height: number} | null {
    if (png.length < 33 || png.length > LIMITS.itemBytes || png.subarray(0,8).toString('hex') !== '89504e470d0a1a0a'
        || png.readUInt32BE(8) !== 13 || png.toString('ascii',12,16) !== 'IHDR') return null;
    const width = png.readUInt32BE(16), height = png.readUInt32BE(20);
    return width > 0 && height > 0 && width * height <= LIMITS.pixels ? {width, height} : null;
}
/** JPEG SOF metadata is read without expanding pixels; only PNG/JPEG reach nativeImage. */
export function imageDimensions(bytes: Buffer): {width: number; height: number} | null {
    const png = pngDimensions(bytes);
    if (png) return png;
    if (bytes.length < 4 || bytes.length > LIMITS.itemBytes || bytes[0] !== 0xff || bytes[1] !== 0xd8) return null;
    let offset = 2;
    while (offset + 4 <= bytes.length) {
        if (bytes[offset++] !== 0xff) return null;
        while (offset < bytes.length && bytes[offset] === 0xff) offset++;
        const marker = bytes[offset++];
        if (marker === 0xda || marker === 0xd9 || marker === undefined) return null;
        if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
        if (offset + 2 > bytes.length) return null;
        const length = bytes.readUInt16BE(offset);
        if (length < 2 || offset + length > bytes.length) return null;
        if ([0xc0,0xc1,0xc2,0xc3,0xc5,0xc6,0xc7,0xc9,0xca,0xcb,0xcd,0xce,0xcf].includes(marker)) {
            if (length < 8) return null;
            const height = bytes.readUInt16BE(offset + 3), width = bytes.readUInt16BE(offset + 5);
            return width > 0 && height > 0 && width * height <= LIMITS.pixels ? {width,height} : null;
        }
        offset += length;
    }
    return null;
}
/** Only the fixed PNG header is decoded when validating bounded private processor data URLs. */
export function boundedPNGDataURL(value:unknown,side:number,maxLength:number):value is string{
    const prefix='data:image/png;base64,';
    if(typeof value!=='string' || value.length>maxLength || !value.startsWith(prefix))return false;
    const header=Buffer.from(value.slice(prefix.length,prefix.length+44),'base64'),size=pngDimensions(header);
    return Boolean(size && size.width<=side && size.height<=side);
}
