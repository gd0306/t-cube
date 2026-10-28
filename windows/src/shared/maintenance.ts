import type { Face } from './contracts';
export interface MaintenanceState { backups: { id: string; name: string }[]; broken: { face: Face; slot: number; name: string; reason: string }[]; status?: string }
export interface ImportPreview { token: string; launcherCount: number; contentCount: number; name: string }
export interface MaintenanceBridge {
    getMaintenanceState(): Promise<MaintenanceState>;
    exportBackup(): Promise<{ status: string }>;
    previewImportBackup(backupId?: string): Promise<ImportPreview | null>;
    confirmImportBackup(token: string): Promise<{ status: string }>;
    createBackup(): Promise<{ status: string }>;
    repairLauncher(request: { face: Face; slot: number }): Promise<void>;
    revealBackups(): Promise<void>;
}
export interface LifecycleState { loginEnabled: boolean; loginSupported: boolean; automaticUpdates: boolean; updatesEnabled: boolean; status: string; version: string; updateReady: boolean; releaseURL: string }
export interface LifecycleBridge {
    getLifecycleState(): Promise<LifecycleState>;
    setLoginEnabled(enabled: boolean): Promise<LifecycleState>;
    setAutomaticUpdates(enabled: boolean): Promise<LifecycleState>;
    checkForUpdates(): Promise<LifecycleState>;
    installUpdate(): Promise<LifecycleState>;
    openReleasePage(): Promise<void>;
}
