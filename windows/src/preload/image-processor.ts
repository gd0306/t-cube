import {contextBridge,ipcRenderer} from 'electron';
contextBridge.exposeInMainWorld('tcubeImageProcessor',{
    onRequest:(callback:(request:unknown)=>void)=>ipcRenderer.on('tcube:private-image-request',(_event,value)=>callback(value)),
    complete:(reply:unknown)=>ipcRenderer.send('tcube:private-image-reply',reply),
});
