export interface DisplayInputMapping { typeC: number; hdmi: number }
export function validMapping(value: unknown): value is DisplayInputMapping {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
    const entry = value as Record<string, unknown>;
    return Object.keys(entry).sort().join(',') === 'hdmi,typeC' && [entry.typeC, entry.hdmi].every(n => typeof n === 'number' && Number.isInteger(n) && n >= 0 && n <= 65535) && entry.typeC !== entry.hdmi;
}
/** Full monitor interface paths only; case does not identify a distinct Windows device. */
export function normalizeIdentity(value: unknown): string {
    if (typeof value !== 'string' || value.length > 512 || !/^\\\\\?\\display#[^#\\]+#[^#\\]+#\{[0-9a-f-]+\}$/i.test(value)) throw new Error('Invalid monitor interface identity');
    return value.toLowerCase();
}
