import { FEATURE_CHANNELS as F } from '../shared/feature-channels';
import { contextBridge, ipcRenderer, webUtils } from 'electron';
import type { DesktopBridge } from '../shared/contracts';
import { CHANNELS } from '../main/ipc';

function subscribe<T>(channel: string, callback: (value: T) => void): () => void {
    const listener = (_event: Electron.IpcRendererEvent, value: T) => callback(value);
    ipcRenderer.on(channel, listener);
    return () => ipcRenderer.removeListener(channel, listener);
}
const bridge: DesktopBridge = {
    showLibrary: text => ipcRenderer.invoke(F.showLibrary,text), getLibrary:()=>ipcRenderer.invoke(F.getLibrary),
    saveSnippet:snippet=>ipcRenderer.invoke(F.saveSnippet,snippet),deleteSnippet:id=>ipcRenderer.invoke(F.deleteSnippet,id),moveSnippet:request=>ipcRenderer.invoke(F.moveSnippet,request),
    useSnippetText:request=>ipcRenderer.invoke(F.useSnippetText,request),captureClipboard:()=>ipcRenderer.invoke(F.captureClipboard),
    onLibraryCapture:callback=>subscribe(F.libraryCapture,callback),onLibraryChanged:callback=>subscribe(F.libraryChanged,callback),
    getMaintenanceState:()=>ipcRenderer.invoke(F.getMaintenanceState),exportBackup:()=>ipcRenderer.invoke(F.exportBackup),previewImportBackup:id=>ipcRenderer.invoke(F.previewImportBackup,id),confirmImportBackup:token=>ipcRenderer.invoke(F.confirmImportBackup,token),createBackup:()=>ipcRenderer.invoke(F.createBackup),repairLauncher:request=>ipcRenderer.invoke(F.repairLauncher,request),revealBackups:()=>ipcRenderer.invoke(F.revealBackups),
    getLifecycleState:()=>ipcRenderer.invoke(F.getLifecycleState),setLoginEnabled:enabled=>ipcRenderer.invoke(F.setLoginEnabled,enabled),setAutomaticUpdates:enabled=>ipcRenderer.invoke(F.setAutomaticUpdates,enabled),checkForUpdates:()=>ipcRenderer.invoke(F.checkForUpdates),installUpdate:()=>ipcRenderer.invoke(F.installUpdate),openReleasePage:()=>ipcRenderer.invoke(F.openReleasePage),
    getPerformanceSettings:()=>ipcRenderer.invoke(F.getPerformanceSettings),setPerformanceSettings:enabled=>ipcRenderer.invoke(F.setPerformanceSettings,enabled),
    getSnapshot: () => ipcRenderer.invoke(CHANNELS.getSnapshot),
    onState: callback => subscribe(CHANNELS.state, callback),
    onIcons: callback => subscribe(CHANNELS.icons, callback),
    onError: callback => subscribe(CHANNELS.error, callback),
    beginPointer: button => ipcRenderer.invoke(CHANNELS.beginPointer, button),
    endPointer: request => ipcRenderer.invoke(CHANNELS.endPointer, request),
    applyConfiguration: configuration => ipcRenderer.invoke(CHANNELS.applyConfiguration, configuration),
    addURLTarget: request => ipcRenderer.invoke(CHANNELS.addURLTarget, request),
    chooseTarget: request => ipcRenderer.invoke(CHANNELS.chooseTarget, request),
    listInstalledApplications: refresh => ipcRenderer.invoke(CHANNELS.listApplications, refresh),
    installedApplicationIcons: ids => ipcRenderer.invoke(CHANNELS.applicationIcons, ids),
    addInstalledApplication: request => ipcRenderer.invoke(CHANNELS.addApplication, request),
    dropTargets: request => ipcRenderer.invoke(CHANNELS.dropTargets, request),
    removeTarget: request => ipcRenderer.invoke(CHANNELS.removeTarget, request),
    moveTarget: request => ipcRenderer.invoke(CHANNELS.moveTarget, request),
    renameGroup: request => ipcRenderer.invoke(CHANNELS.renameGroup, request),
    launch: request => ipcRenderer.invoke(CHANNELS.launch, request),
    place: placement => ipcRenderer.invoke(CHANNELS.place, placement),
    showSettings: () => ipcRenderer.invoke(CHANNELS.showSettings),
    quit: () => ipcRenderer.invoke(CHANNELS.quit),
    closeExpanded: () => ipcRenderer.invoke(CHANNELS.closeExpanded),
    getDroppedPaths: files => files.map(file => webUtils.getPathForFile(file)).filter(Boolean)
};
contextBridge.exposeInMainWorld('tcube', bridge);
