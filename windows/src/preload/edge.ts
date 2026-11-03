import {contextBridge,ipcRenderer} from 'electron';
import {EDGE_VISIBILITY_CHANNEL,type EdgeVisibilityBridge} from '../shared/edge-visibility';
let visible=false;
const subscribers=new Set<(visible:boolean)=>void>();
ipcRenderer.on(EDGE_VISIBILITY_CHANNEL,(_event,value:unknown)=>{
    if(typeof value!=='boolean')return;
    visible=value;
    for(const callback of subscribers)callback(visible);
});
const bridge:EdgeVisibilityBridge={
    onVisibility(callback){subscribers.add(callback);callback(visible);return()=>{subscribers.delete(callback);};},
};
contextBridge.exposeInMainWorld('tcubeEdge',bridge);
