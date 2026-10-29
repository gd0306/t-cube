/** Built-in Windows settings pages. Renderer selection and host validation share this allowlist. */
export const SYSTEM_SETTINGS = [
    { id: 'wifi', name: 'Wi-Fi', uri: 'ms-settings:network-wifi' },
    { id: 'bluetooth', name: '蓝牙', uri: 'ms-settings:bluetooth' },
    { id: 'display', name: '显示', uri: 'ms-settings:display' },
    { id: 'sound', name: '声音', uri: 'ms-settings:sound' },
    { id: 'privacy', name: '隐私', uri: 'ms-settings:privacy' },
    { id: 'keyboard', name: '键盘', uri: 'ms-settings:easeofaccess-keyboard' },
] as const;

export function websiteURL(value: string): URL {
    if (typeof value !== 'string' || value.length > 8192 || /[\s\\\x00-\x1f\x7f]/.test(value)) throw new Error('Invalid website URL');
    const authority = /^https?:\/\/([^/?#]+)/i.exec(value)?.[1];
    if (!authority || authority.includes('@')) throw new Error('Invalid website URL');
    let url: URL;
    try { url = new URL(value); } catch { throw new Error('Invalid website URL'); }
    if (!['http:', 'https:'].includes(url.protocol) || !url.hostname || url.username || url.password) throw new Error('Invalid website URL');
    return url;
}
export function systemSettingsTarget(value: string): typeof SYSTEM_SETTINGS[number] {
    const page = SYSTEM_SETTINGS.find(page => page.uri === value);
    if (!page) throw new Error('Invalid system settings target');
    return page;
}
export function isURLTarget(kind: string): boolean { return kind === 'website' || kind === 'systemSettings'; }
