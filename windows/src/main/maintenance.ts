import { isURLTarget } from '../shared/shortcut-targets';
import { readFile, mkdir } from 'node:fs/promises';
import { basename } from 'node:path';
import { randomUUID } from 'node:crypto';
import { FACES, type Configuration, type Face } from '../shared/contracts';
import type { MaintenanceBridge, MaintenanceState, ImportPreview } from '../shared/maintenance';
import { validateLocalTarget, validateTarget } from './targets';
import { ConfigurationArchiveStore, validateArchive, type ConfigurationArchive } from '../core/configuration-archive';

/** Scan with the same kind/path policy used for launch, rather than mere existence. */
export async function scanBrokenLaunchers(config: Configuration, validate: typeof validateLocalTarget = validateLocalTarget): Promise<MaintenanceState['broken']> {
    const found = await Promise.all(FACES.flatMap(face => config.groups[face].slots.map(async (item, slot) => {
        if (!item) return null;
        try { await (isURLTarget(item.kind) ? validateTarget(item.path, item.kind) : validate(item.path, item.kind)); return null; }
        catch { return { face, slot, name: item.name, reason: '目标不存在、类型已变更或无法访问，请重新关联。' }; }
    })));
    return found.filter((item): item is NonNullable<typeof item> => item !== null);
}
export interface MaintenanceOptions {
    configurationPath: string; libraryPath: string;
    getConfiguration: () => Configuration;
    afterRestore: (configuration: Configuration) => Promise<void>;
    repairLauncher: (request: { face: Face; slot: number }) => Promise<void>;
}
/** Renderer receives opaque backup IDs and single-use previews, never filesystem authority. */
export class MaintenanceService implements MaintenanceBridge {
    readonly archives: ConfigurationArchiveStore;
    private backupIndex = new Map<string, string>();
    private pending: { token: string; archive: ConfigurationArchive; expires: number } | null = null;
    private restoring = false;
    private status: string | undefined;
    get isRestoring() { return this.restoring; }
    constructor(private readonly options: MaintenanceOptions) { this.archives = new ConfigurationArchiveStore(options.configurationPath, options.libraryPath); }
    async getMaintenanceState(): Promise<MaintenanceState> {
        this.backupIndex.clear();
        const backups = (await this.archives.backups()).map(path => { const id = randomUUID(); this.backupIndex.set(id, path); return { id, name: basename(path) }; });
        const broken = await scanBrokenLaunchers(this.options.getConfiguration());
        return { backups, broken, status: this.status };
    }
    async exportBackup() {
        const { dialog } = await import('electron');
        const result = await dialog.showSaveDialog({ title: '导出 T-Cube 备份', defaultPath: 'T-Cube-backup.json', filters: [{ name: 'T-Cube 备份', extensions: ['json'] }] });
        if (result.canceled || !result.filePath) return { status: '已取消导出。' };
        await this.archives.export(result.filePath); return { status: this.status = '备份已导出。' };
    }
    async previewImportBackup(backupId?: string): Promise<ImportPreview | null> {
        if (backupId !== undefined && (typeof backupId !== 'string' || backupId.length > 100)) throw new Error('Invalid backup ID');
        this.pending = null;
        let path: string | undefined;
        if (backupId !== undefined) { path = this.backupIndex.get(backupId); if (!path) throw new Error('备份已变更，请刷新列表。'); }
        else {
            const { dialog } = await import('electron');
            const result = await dialog.showOpenDialog({ title: '导入 T-Cube 备份', properties: ['openFile'], filters: [{ name: 'T-Cube 备份', extensions: ['json'] }] });
            if (result.canceled) return null; path = result.filePaths[0];
        }
        if (!path) return null;
        const data = await readFile(path); if (data.length > 16 * 1024 * 1024) throw new Error('备份文件过大。');
        const archive = validateArchive(JSON.parse(data.toString('utf8')));
        await this.archives.currentArchive();
        const token = randomUUID(); this.pending = { token, archive, expires: Date.now() + 5 * 60_000 };
        return { token, name: basename(path), launcherCount: FACES.reduce((count, face) => count + archive.configuration.groups[face].slots.filter(Boolean).length, 0), contentCount: archive.contentLibrary.items.length };
    }
    async confirmImportBackup(token: string) {
        if (typeof token !== 'string' || token.length > 100) throw new Error('Invalid import token');
        if (this.restoring) throw new Error('正在恢复，请稍候。');
        const pending = this.pending; this.pending = null;
        if (!pending || pending.token !== token || pending.expires < Date.now()) throw new Error('恢复预览已失效，请重新选择备份。');
        this.restoring = true;
        try {
            await this.archives.restore(pending.archive);
            await this.options.afterRestore(pending.archive.configuration);
            return { status: this.status = '已恢复分组与常用内容，原数据已自动备份。' };
        } finally { this.restoring = false; }
    }
    async createBackup() { await this.archives.makeBackup(); return { status: this.status = '本地备份已创建。' }; }
    async repairLauncher(request: { face: Face; slot: number }) {
        if (!request || typeof request !== 'object' || !FACES.includes(request.face) || !Number.isInteger(request.slot) || request.slot < 0 || request.slot > 3) throw new Error('Invalid launcher');
        if (this.restoring) throw new Error('正在恢复，请稍候。'); await this.options.repairLauncher(request);
    }
    async revealBackups() { const { shell } = await import('electron'); await mkdir(this.archives.backupsPath, { recursive: true }); const result = await shell.openPath(this.archives.backupsPath); if (result) throw new Error(result); }
}
