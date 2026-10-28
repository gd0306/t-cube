export const FEATURE_CHANNELS = {
    showLibrary:'tcube:library-show', getLibrary:'tcube:library-get', saveSnippet:'tcube:library-save',
    deleteSnippet:'tcube:library-delete',moveSnippet:'tcube:library-move',useSnippetText:'tcube:library-use',captureClipboard:'tcube:clipboard-capture',
    libraryCapture:'tcube:library-capture',libraryChanged:'tcube:library-changed',
    getMaintenanceState:'tcube:maintenance-state',exportBackup:'tcube:backup-export',previewImportBackup:'tcube:backup-preview',confirmImportBackup:'tcube:backup-confirm',createBackup:'tcube:backup-create',repairLauncher:'tcube:launcher-repair',revealBackups:'tcube:backup-reveal',
    getLifecycleState:'tcube:lifecycle-state',setLoginEnabled:'tcube:login-set',setAutomaticUpdates:'tcube:updates-set',checkForUpdates:'tcube:updates-check',installUpdate:'tcube:updates-install',openReleasePage:'tcube:releases-open',
    getPerformanceSettings:'tcube:performance-get',setPerformanceSettings:'tcube:performance-set'
} as const;
