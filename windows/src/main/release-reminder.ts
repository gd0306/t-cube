import { open } from 'node:fs/promises';
import { atomicWriteJSON } from '../core/atomic-json';
import type { LifecycleBridge, LifecycleState } from '../shared/maintenance';

const RELEASES = 'https://github.com/gd0306/t-cube/releases';
const API = 'https://api.github.com/repos/gd0306/t-cube/releases/latest';
const INTERVAL = 6 * 60 * 60_000;
const DAY = 24 * 60 * 60_000;
export interface ReminderPreferences { version: 1; enabled: boolean; lastAttempt: number | null; lastNotified: string | null; retryUntil: number | null }
const defaults = (): ReminderPreferences => ({ version: 1, enabled: false, lastAttempt: null, lastNotified: null, retryUntil: null });
function versionParts(value: unknown): number[] | null {
    if (typeof value !== 'string' || !/^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(value)) return null;
    const parts = value.replace(/^v/, '').split('.').map(Number);
    return parts.every(Number.isSafeInteger) ? parts : null;
}
function isNewer(candidate: string, baseline: string): boolean {
    const remote = versionParts(candidate), local = versionParts(baseline);
    if (!remote || !local) return false;
    const different = remote.findIndex((part, index) => part !== local[index]);
    return different !== -1 && remote[different] > local[different];
}
export interface ReminderRelease { version: string; tag: string; url: string }
function validateReminderRelease(value: unknown): ReminderRelease | null {
    if (!value || typeof value !== 'object') return null;
    const release = value as Record<string, unknown>;
    const remote = versionParts(release.tag_name);
    if (!remote || release.draft !== false || release.prerelease !== false) return null;
    const tag = release.tag_name as string, url = `${RELEASES}/tag/${tag}`;
    if (release.html_url !== url) return null;
    return { version: remote.join('.'), tag, url };
}
export function parseReminderRelease(value: unknown, current: string): ReminderRelease | null {
    const release = validateReminderRelease(value);
    return release && isNewer(release.version, current) ? release : null;
}
function validPreferences(value: unknown): value is ReminderPreferences {
    if (!value || typeof value !== 'object') return false;
    const data = value as ReminderPreferences;
    return data.version === 1 && typeof data.enabled === 'boolean'
        && [data.lastAttempt, data.retryUntil].every(time => time === null || (Number.isSafeInteger(time) && time >= 0))
        && (data.lastNotified === null || !!versionParts(data.lastNotified));
}
/** The first read validates existing data. A corrupt file is never overwritten. */
export class ReminderStore {
    private loaded: Promise<ReminderPreferences> | undefined;
    private writes = Promise.resolve();
    constructor(private readonly path: string) {}
    read(): Promise<ReminderPreferences> {
        this.loaded ??= (async () => {
            try {
                const file = await open(this.path, 'r');
                try {
                    // Fixed-size incremental reads also bound allocation if a file grows after opening.
                    const limit = 16 * 1024, bytes = Buffer.alloc(limit + 1); let length = 0;
                    while (length < bytes.length) {
                        const { bytesRead } = await file.read(bytes, length, bytes.length - length, null);
                        if (!bytesRead) break; length += bytesRead;
                    }
                    if (length > limit) throw new Error('Reminder preferences too large');
                    const value: unknown = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes.subarray(0, length)));
                    if (!validPreferences(value)) throw new Error('Invalid reminder preferences'); return value;
                } finally { await file.close(); }
            }
            catch (error) { if ((error as NodeJS.ErrnoException).code === 'ENOENT') return defaults(); throw error; }
        })();
        return this.loaded.then(value => structuredClone(value));
    }
    write(value: ReminderPreferences): Promise<void> {
        const snapshot = structuredClone(value);
        const operation = this.writes.then(async () => { await this.read(); if (!validPreferences(snapshot)) throw new Error('Invalid reminder preferences'); await atomicWriteJSON(this.path, snapshot); });
        this.writes = operation.catch(() => {}); return operation;
    }
}
class RateLimitError extends Error { constructor(readonly retryUntil: number) { super('发布服务请求过于频繁，请稍后再试。'); } }
export type ReleaseTransport = (url: string, init: RequestInit) => Promise<Response>;
/** Anonymous metadata request only: no assets, credentials, redirects, or installer operations. */
export async function fetchLatestRelease(signal: AbortSignal, transport: ReleaseTransport = fetch, now: () => number = Date.now): Promise<unknown> {
    const controller = new AbortController();
    const abort = () => controller.abort();
    signal.addEventListener('abort', abort, { once: true }); if (signal.aborted) controller.abort();
    const timeout = setTimeout(abort, 15_000); timeout.unref?.();
    let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
    try {
        const response = await transport(API, { signal: controller.signal, redirect: 'error', credentials: 'omit', headers: { Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'T-Cube-release-reminder' } });
        if (response.status === 403 || response.status === 429) {
            const time = now(), retry = response.headers.get('Retry-After'), reset = response.headers.get('X-RateLimit-Reset');
            const retryDate = retry && !/^\d+$/.test(retry) ? Date.parse(retry) : NaN;
            const retryTime = retry && /^\d+$/.test(retry) ? time + Number(retry) * 1000 : retryDate;
            const resetTime = reset && /^\d+$/.test(reset) ? Number(reset) * 1000 : NaN;
            const deadlines = [retryTime, resetTime].filter(Number.isFinite);
            const requested = deadlines.length ? Math.max(...deadlines) : time + 60 * 60_000;
            throw new RateLimitError(Math.min(time + DAY, Math.max(time + 60_000, requested)));
        }
        if (!response.ok || response.redirected || (response.url && response.url !== API) || !response.body) throw new Error('Release request failed');
        const limit = 512 * 1024;
        if (Number(response.headers.get('Content-Length')) > limit) throw new Error('Release response too large');
        reader = response.body.getReader();
        const chunks: Uint8Array[] = []; let length = 0;
        while (true) {
            if (controller.signal.aborted) throw new Error('Release request cancelled');
            const chunk = await reader.read(); if (chunk.done) break;
            length += chunk.value.byteLength; if (length > limit) throw new Error('Release response too large'); chunks.push(chunk.value);
        }
        const bytes = new Uint8Array(length); let offset = 0;
        for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
        return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
    } finally {
        clearTimeout(timeout); signal.removeEventListener('abort', abort);
        if (reader) { await reader.cancel().catch(() => {}); reader.releaseLock(); }
        controller.abort();
    }
}
export interface ReminderOptions {
    platform: string; packaged: boolean; version: string;
    store: { read(): Promise<ReminderPreferences>; write(value: ReminderPreferences): Promise<void> };
    getLogin(): boolean; setLogin(enabled: boolean): void | Promise<void>; getLoginStatus?(): string;
    fetchRelease(signal: AbortSignal): Promise<unknown>;
    notify(release: ReminderRelease): Promise<boolean>;
    open(url: string): Promise<void>;
    onDispose?: () => void;
    now?: () => number;
    schedule?: (callback: () => void, delay: number) => unknown;
    cancel?: (timer: any) => void;
}
export class ReleaseReminderController implements LifecycleBridge {
    private preferences = defaults();
    private loaded: Promise<void> | undefined;
    private blocked = false;
    private disposed = false;
    private paused = false;
    private status = '自动检查默认关闭；可手动检查新版本并前往发布页下载。';
    private latest: ReminderRelease | null = null;
    private timer: unknown = null;
    private flight: Promise<void> | null = null;
    private abort: AbortController | null = null;
    private generation = 0;
    private mutations = Promise.resolve();
    private automaticPreferenceChanges = 0;
    private readonly supported: boolean;
    private readonly now: () => number;
    private readonly scheduleTimer: (callback: () => void, delay: number) => unknown;
    private readonly cancelTimer: (timer: any) => void;
    constructor(private readonly options: ReminderOptions) {
        this.supported = options.platform === 'win32' && options.packaged;
        this.now = options.now ?? Date.now;
        this.scheduleTimer = options.schedule ?? ((callback, delay) => { const timer = setTimeout(callback, delay); timer.unref(); return timer; });
        this.cancelTimer = options.cancel ?? clearTimeout;
    }
    private load() {
        this.loaded ??= this.options.store.read().then(value => { if (!validPreferences(value)) throw new Error('Invalid preferences'); this.preferences = value; if (value.enabled) this.status = '已开启版本提醒，每 6 小时检查一次。'; }).catch(() => { this.blocked = true; this.status = '更新提醒设置无法读取，已停止检查并保留原文件。'; });
        return this.loaded;
    }
    private mutate(change: (preferences: ReminderPreferences) => ReminderPreferences) {
        const operation = this.mutations.then(async () => { await this.load(); if (this.blocked) throw new Error('更新提醒设置不可用，请先修复原文件。'); const value = change(this.preferences);
            try { await this.options.store.write(value); this.preferences = value; }
            catch { this.blocked = true; this.status = '更新提醒设置无法保存，已停止检查并保留原文件。'; this.invalidate(); throw new Error(this.status); } });
        this.mutations = operation.catch(() => {}); return operation;
    }
    async getLifecycleState(): Promise<LifecycleState> {
        await this.load();
        return { loginEnabled: this.supported ? this.options.getLogin() : false, loginSupported: this.supported, automaticUpdates: this.preferences.enabled && this.supported && !this.blocked,
            updatesEnabled: false, updateReady: false, updateMode: 'reminder', checksSupported: this.supported && !this.blocked, latestVersion: this.latest?.version, isChecking: !!this.flight,
            status: this.supported ? [this.options.getLoginStatus?.(), this.status].filter(Boolean).join(' ') : '发布提醒仅支持 Windows 安装版。请从发布页面手动下载。', version: this.options.version, releaseURL: RELEASES };
    }
    async setLoginEnabled(enabled: boolean) {
        if (typeof enabled !== 'boolean') throw new Error('Invalid login preference');
        if (!this.supported) throw new Error('登录启动仅支持 Windows 安装版。');
        await this.options.setLogin(enabled); return this.getLifecycleState();
    }
    async setAutomaticUpdates(enabled: boolean) {
        if (typeof enabled !== 'boolean') throw new Error('Invalid update preference');
        if (!this.supported) throw new Error('发布提醒仅支持 Windows 安装版。');
        // Gate startup/resume synchronously while a preference change is still on disk.
        this.automaticPreferenceChanges++;
        if (!enabled) this.invalidate();
        try { await this.mutate(value => ({ ...value, enabled })); }
        finally { this.automaticPreferenceChanges--; }
        if (enabled) await this.start(); else this.clearTimer();
        return this.getLifecycleState();
    }
    private clearTimer() { if (this.timer !== null) this.cancelTimer(this.timer); this.timer = null; }
    private invalidate() { this.generation++; this.abort?.abort(); this.clearTimer(); }
    /** Called for OS suspend/resume as well as shutdown so a late request cannot prompt. */
    pause() { this.paused = true; this.invalidate(); }
    async resume() { this.paused = false; await this.start(); }
    dispose() { if (this.disposed) return; this.disposed = true; this.invalidate(); this.options.onDispose?.(); }
    private canAuto() { return this.supported && !this.blocked && !this.disposed && !this.paused && this.automaticPreferenceChanges === 0 && this.preferences.enabled; }
    private lastAttempt() {
        // A clock rollback must not suppress checks until the former wall clock catches up.
        return this.preferences.lastAttempt !== null && this.preferences.lastAttempt <= this.now() ? this.preferences.lastAttempt : null;
    }
    private due() { const lastAttempt = this.lastAttempt(); return Math.max(lastAttempt === null ? 0 : lastAttempt + INTERVAL, this.preferences.retryUntil ?? 0); }
    async start() {
        await this.load();
        if (!this.canAuto()) return;
        if (this.due() <= this.now()) await this.check(true);
        this.schedule();
    }
    private schedule() {
        this.clearTimer();
        if (this.canAuto()) this.timer = this.scheduleTimer(() => { this.timer = null; void this.check(true).finally(() => this.schedule()); }, Math.max(1, Math.min(DAY, this.due() - this.now())));
    }
    private async check(automatic: boolean) {
        await this.load();
        if (this.flight) return this.flight;
        if (!this.supported || this.blocked || this.disposed || this.paused || (automatic && !this.canAuto())) return;
        if ((this.preferences.retryUntil ?? 0) > this.now()) { this.status = '发布服务暂时限制请求，请稍后再试。'; return; }
        const lastAttempt = this.lastAttempt();
        if (lastAttempt !== null && this.now() - lastAttempt < (automatic ? INTERVAL : 60_000)) { this.status = '刚刚已检查，请稍后再试。'; return; }
        const generation = this.generation;
        const controller = new AbortController(); this.abort = controller;
        this.flight = (async () => {
            try {
                await this.mutate(value => ({ ...value, lastAttempt: this.now() }));
                if (controller.signal.aborted || generation !== this.generation || (automatic && !this.canAuto())) return;
                this.status = '正在检查新版本…';
                const value = await this.options.fetchRelease(controller.signal);
                if (controller.signal.aborted || generation !== this.generation) return;
                if (!validateReminderRelease(value) || !versionParts(this.options.version)) throw new Error('Invalid release metadata');
                this.latest = parseReminderRelease(value, this.options.version);
                this.status = this.latest ? `发现新版本 ${this.latest.version}，可前往发布页手动下载。` : '当前未发现更新的稳定版本。';
                if (automatic && this.canAuto() && this.latest && (this.preferences.lastNotified === null || isNewer(this.latest.version, this.preferences.lastNotified))) {
                    const release = this.latest;
                    const open = await this.options.notify(release);
                    if (generation !== this.generation || !this.canAuto()) return;
                    await this.mutate(value => ({ ...value, lastNotified: release.version }));
                    if (open && generation === this.generation && this.canAuto()) await this.options.open(release.url);
                }
            } catch (error) {
                if (controller.signal.aborted || generation !== this.generation) return;
                if (error instanceof RateLimitError) { await this.mutate(value => ({ ...value, retryUntil: error.retryUntil })).catch(() => {}); this.status = error.message; }
                else if (!this.blocked) this.status = '检查新版本失败，请稍后再试。';
            }
        })().finally(() => { this.flight = null; if (this.abort === controller) this.abort = null; this.schedule(); });
        return this.flight;
    }
    async checkForUpdates() { await this.check(false); return this.getLifecycleState(); }
    async installUpdate() { return this.getLifecycleState(); }
    openReleasePage() { return this.options.open(this.latest?.url ?? RELEASES); }
}
