import { contextBridge, ipcRenderer, webUtils } from 'electron';
import type { DesktopBridge } from '../shared/contracts';
import { CHANNELS } from '../main/ipc';

function subscribe<T>(channel: string, callback: (value: T) => void): () => void {
    const listener = (_event: Electron.IpcRendererEvent, value: T) => callback(value);
    ipcRenderer.on(channel, listener);
    return () => ipcRenderer.removeListener(channel, listener);
}
const bridge: DesktopBridge = {
    getSnapshot: () => ipcRenderer.invoke(CHANNELS.getSnapshot),
    onState: callback => subscribe(CHANNELS.state, callback),
    onIcons: callback => subscribe(CHANNELS.icons, callback),
    onError: callback => subscribe(CHANNELS.error, callback),
    beginPointer: button => ipcRenderer.invoke(CHANNELS.beginPointer, button),
    endPointer: request => ipcRenderer.invoke(CHANNELS.endPointer, request),
    applyConfiguration: configuration => ipcRenderer.invoke(CHANNELS.applyConfiguration, configuration),
    chooseTarget: request => ipcRenderer.invoke(CHANNELS.chooseTarget, request),
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
