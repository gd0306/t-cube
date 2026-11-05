import { normalizeIdentity, validMapping, type DisplayInputMapping } from '../shared/display-input';
export interface PanelRequests {
    list(): Promise<unknown>;
    save(identity: string, mapping: DisplayInputMapping): Promise<unknown>;
    switch(identity: string, target: 'typeC' | 'hdmi'): Promise<unknown>;
    close(): void;
}
export function isPanelSender(window: { isDestroyed(): boolean; webContents: { mainFrame: unknown } } | null, sender: unknown, frame: unknown): boolean {
    return !!window && !window.isDestroyed() && sender === window.webContents && frame === window.webContents.mainFrame;
}
/** Authorization precedes payload parsing and all service/native operations. */
export async function handleDisplayInputRequest(channel: string, authorized: boolean, payload: unknown, service: PanelRequests): Promise<unknown> {
    if (!authorized) throw new Error('Unauthorized display input request');
    if (channel === 'close') { if (payload !== undefined) throw new Error('Invalid request'); service.close(); return; }
    if (channel === 'list') { if (payload !== undefined) throw new Error('Invalid request'); return service.list(); }
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) throw new Error('Invalid display input request');
    const data = payload as Record<string, unknown>; const identity = normalizeIdentity(data.identity);
    if (channel === 'save' && Object.keys(data).sort().join(',') === 'identity,mapping' && validMapping(data.mapping)) return service.save(identity, data.mapping);
    if (channel === 'switch' && Object.keys(data).sort().join(',') === 'identity,target' && (data.target === 'typeC' || data.target === 'hdmi')) return service.switch(identity, data.target);
    throw new Error('Invalid display input request');
}
