/** Accept only a complete EDID base block with a valid checksum and exact model descriptor. */
export function isKnownModelEdid(bytes: Uint8Array): boolean {
    if (bytes.length < 128 || bytes.length > 1024 || ![0, 255, 255, 255, 255, 255, 255, 0].every((value, index) => bytes[index] === value)) return false;
    if (bytes.subarray(0, 128).reduce((sum, value) => sum + value, 0) % 256 !== 0) return false;
    // IOC vendor 9699, product FFFF; the generic marker alone is insufficient.
    if (bytes[8] !== 0x25 || bytes[9] !== 0xe3 || bytes[10] !== 0xff || bytes[11] !== 0xff) return false;
    for (let offset = 54; offset <= 108; offset += 18) {
        if (bytes[offset] !== 0 || bytes[offset + 1] !== 0 || bytes[offset + 2] !== 0 || bytes[offset + 3] !== 0xfc || bytes[offset + 4] !== 0) continue;
        const name = Buffer.from(bytes.subarray(offset + 5, offset + 18)).toString('ascii').split(/[\n\0]/, 1)[0].trim();
        if (name.toUpperCase() === '27C1U-D') return true;
    }
    return false;
}
