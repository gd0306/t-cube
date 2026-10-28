import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import type { LifecycleBridge, LifecycleState } from '../shared/maintenance';
import { atomicWrite } from '../core/configuration-archive';

export const RELEASE_URL = 'https://github.com/gd0306/t-cube/releases';
export function updatePolicy(platform: string, packaged: boolean, publishers: string[]): { enabled: boolean; status: string } {
    if (platform !== 'win32') return { enabled: false, status: '当前为非 Windows 预览，登录启动和自动更新不可用。' };
    if (!packaged) return { enabled: false, status: '开发预览不检查更新。请从发布页面安装正式版。' };
    if (!publishers.length || publishers.some(name => !name.trim())) return { enabled: false, status: '当前版本未配置受信任的签名发布者，自动更新已停用。请从发布页面手动下载。' };
    return { enabled: true, status: '仅接受配置发布者的 Authenticode 签名更新。' };
}
/** Fail closed if packaging omits publisherName: upstream otherwise skips Authenticode checks. */
export function validateUpdateConfiguration(value: unknown, publisher: string): void {
    if (!value || typeof value !== 'object') throw new Error('Missing signed update configuration');
    const config = value as Record<string, unknown>;
    const publishers = Array.isArray(config.publisherName) ? config.publisherName : [config.publisherName];
    if (config.provider !== 'github' || config.owner !== 'gd0306' || config.repo !== 't-cube'
        || config.protocol !== 'https' || config.private === true || config.token !== undefined
        || publishers.length !== 1 || publishers[0] !== publisher || !publisher.trim())
        throw new Error('Packaged update feed or publisher identity does not match the trusted release configuration');
}
interface Updater {
    autoDownload: boolean; autoInstallOnAppQuit: boolean;
    checkForUpdates(): Promise<{ isUpdateAvailable?: boolean; updateInfo?: { version: string } } | null>;
    downloadUpdate(): Promise<unknown>;
    quitAndInstall(isSilent?: boolean, isForceRunAfter?: boolean): void;
    on(event: string, callback: (...args: any[]) => void): unknown;
}
export interface LifecycleOptions {
    platform: string; packaged: boolean; version: string; publishers: string[];
    getLogin(): boolean; setLogin(enabled: boolean): void;
    readAutomaticUpdates(): Promise<boolean>; writeAutomaticUpdates(enabled: boolean): Promise<void>;
    updater(): Promise<Updater> | Updater;
    confirmDownload(version: string): Promise<boolean>; confirmInstall(): Promise<boolean>;
    openReleasePage(): Promise<void>;
}
export class LifecycleController implements LifecycleBridge {
    private automatic = false;
    private loaded = false;
    private ready = false;
    private busy = false;
    private activeUpdater: Updater | null = null;
    private status: string;
    private timer: ReturnType<typeof setTimeout> | null = null;
    private readonly policy: ReturnType<typeof updatePolicy>;
    constructor(private readonly options: LifecycleOptions) { this.policy = updatePolicy(options.platform, options.packaged, options.publishers); this.status = this.policy.status; }
    private async load() { if (!this.loaded) { this.automatic = await this.options.readAutomaticUpdates(); this.loaded = true; } }
    async getLifecycleState(): Promise<LifecycleState> {
        await this.load();
        return { loginEnabled: this.options.platform === 'win32' && this.options.packaged ? this.options.getLogin() : false, loginSupported: this.options.platform === 'win32' && this.options.packaged,
            automaticUpdates: this.automatic && this.policy.enabled, updatesEnabled: this.policy.enabled, status: this.status, version: this.options.version, updateReady: this.ready, releaseURL: RELEASE_URL };
    }
    async setLoginEnabled(enabled: boolean) {
        if (typeof enabled !== 'boolean') throw new Error('Invalid login preference');
        if (this.options.platform !== 'win32' || !this.options.packaged) throw new Error('登录启动仅支持 Windows 安装版。');
        this.options.setLogin(enabled); return this.getLifecycleState();
    }
    async setAutomaticUpdates(enabled: boolean) {
        if (typeof enabled !== 'boolean') throw new Error('Invalid update preference');
        if (enabled && !this.policy.enabled) throw new Error(this.policy.status);
        await this.load(); await this.options.writeAutomaticUpdates(enabled); this.automatic = enabled;
        this.schedule(); return this.getLifecycleState();
    }
    /** One low-frequency timer; no polling until the user opts in. Downloads always ask first. */
    async start() { await this.load(); this.schedule(); }
    private schedule() {
        if (this.timer) clearTimeout(this.timer); this.timer = null;
        if (this.automatic && this.policy.enabled) { this.timer = setTimeout(() => { this.timer = null; void this.checkForUpdates().catch(error => { this.status = `自动检查失败：${error instanceof Error ? error.message : String(error)}`; }).finally(() => this.schedule()); }, 6 * 60 * 60_000); this.timer.unref(); }
    }
    dispose() { if (this.timer) clearTimeout(this.timer); this.timer = null; }
    private async updater() {
        if (!this.activeUpdater) {
            const updater = await this.options.updater(); updater.autoDownload = false; updater.autoInstallOnAppQuit = false;
            updater.on('error', (error: Error) => { this.status = `更新失败：${error.message}`; });
            updater.on('update-downloaded', () => { this.ready = true; this.status = '更新已验证并下载，可选择重启安装。'; });
            this.activeUpdater = updater;
        }
        return this.activeUpdater;
    }
    async checkForUpdates() {
        if (!this.policy.enabled || this.busy) return this.getLifecycleState();
        this.busy = true;
        try {
            this.status = '正在检查更新…'; const updater = await this.updater(); const result = await updater.checkForUpdates();
            if (result?.isUpdateAvailable) {
                const version = result.updateInfo?.version ?? '';
                this.status = `发现新版本 ${version}。`;
                if (await this.options.confirmDownload(version)) { this.status = '正在下载并验证签名…'; await updater.downloadUpdate(); this.ready = true; this.status = '更新已验证并下载，可选择重启安装。'; }
            } else this.status = '当前已是最新版本。';
        } catch (error) { this.status = `更新失败：${error instanceof Error ? error.message : String(error)}`; }
        finally { this.busy = false; }
        return this.getLifecycleState();
    }
    async installUpdate() {
        if (!this.policy.enabled || !this.ready || this.busy) return this.getLifecycleState();
        if (await this.options.confirmInstall()) (await this.updater()).quitAndInstall(false, true);
        return this.getLifecycleState();
    }
    openReleasePage() { return this.options.openReleasePage(); }
}
/** Electron is loaded here, leaving policy and preferences testable without a desktop session. */
export async function createLifecycleService(): Promise<LifecycleController> {
    const { app, dialog, shell } = await import('electron');
    let publisher = '';
    try { const metadata = JSON.parse(await readFile(join(app.getAppPath(), 'package.json'), 'utf8')); if (typeof metadata.tcubeUpdatePublisher === 'string') publisher = metadata.tcubeUpdatePublisher.trim(); } catch { /* Absence safely disables updates. */ }
    const preferencePath = join(app.getPath('userData'), 'lifecycle-preferences.json');
    const controller = new LifecycleController({ platform: process.platform, packaged: app.isPackaged, version: app.getVersion(), publishers: publisher ? [publisher] : [],
        getLogin: () => app.getLoginItemSettings({ path: process.execPath }).openAtLogin,
        setLogin: enabled => app.setLoginItemSettings({ openAtLogin: enabled, path: process.execPath }),
        readAutomaticUpdates: async () => {
            try { const value = JSON.parse(await readFile(preferencePath, 'utf8')); return value.version === 1 && value.automaticUpdates === true; }
            catch (error) { if ((error as NodeJS.ErrnoException).code === 'ENOENT') return false; return false; }
        },
        writeAutomaticUpdates: enabled => atomicWrite(preferencePath, JSON.stringify({ version: 1, automaticUpdates: enabled })),
        updater: async () => {
            const { autoUpdater } = await import('electron-updater');
            // Pinned 6.8.11 exposes the exact config used by NsisUpdater's verifier through
            // AppUpdater's protected Lazy. Validate it before allowing any network request.
            const configured = autoUpdater as unknown as { configOnDisk: { value: Promise<unknown> } };
            validateUpdateConfiguration(await configured.configOnDisk.value, publisher);
            return autoUpdater as unknown as Updater;
        },
        confirmDownload: async version => (await dialog.showMessageBox({ type: 'question', title: 'T-Cube 更新', message: `下载版本 ${version}？`, detail: '下载后会验证发布者签名。安装前仍会再次确认。', buttons: ['下载', '稍后'], defaultId: 1, cancelId: 1 })).response === 0,
        confirmInstall: async () => (await dialog.showMessageBox({ type: 'question', title: '安装更新', message: '立即退出 T-Cube 并安装已验证的更新？', buttons: ['重启并安装', '稍后'], defaultId: 1, cancelId: 1 })).response === 0,
        openReleasePage: () => shell.openExternal(RELEASE_URL),
    });
    await controller.start(); return controller;
}
