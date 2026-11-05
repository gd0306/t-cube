import { contextBridge, ipcRenderer } from 'electron';
contextBridge.exposeInMainWorld('displayInput', {
    list: () => ipcRenderer.invoke('display-input:list'),
    save: (identity: string, mapping: unknown) => ipcRenderer.invoke('display-input:save', { identity, mapping }),
    switch: (identity: string, target: string) => ipcRenderer.invoke('display-input:switch', { identity, target }),
    close: () => ipcRenderer.invoke('display-input:close')
});
