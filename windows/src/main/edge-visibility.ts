import {EDGE_VISIBILITY_CHANNEL} from '../shared/edge-visibility';
interface EdgeVisibilityWindow {
    isVisible():boolean;
    isDestroyed():boolean;
    on(event:'show'|'hide'|'closed',listener:()=>void):unknown;
    removeListener(event:'show'|'hide'|'closed',listener:()=>void):unknown;
    webContents:{
        isDestroyed():boolean;
        on(event:'did-finish-load',listener:()=>void):unknown;
        removeListener(event:'did-finish-load',listener:()=>void):unknown;
        send(channel:string,visible:boolean):void;
    };
}
/** Native visibility owns resource use even when a capture/debugger leaves Page Visibility reporting visible. */
export function bindEdgeVisibility(window:EdgeVisibilityWindow):()=>void{
    const contents=window.webContents;
    let previous:boolean|undefined;
    const publish=(force=false)=>{
        if(window.isDestroyed() || contents.isDestroyed())return;
        const visible=window.isVisible();
        if(force || visible!==previous){previous=visible;contents.send(EDGE_VISIBILITY_CHANNEL,visible);}
    };
    const changed=()=>publish();
    const loaded=()=>publish(true);
    const dispose=()=>{
        window.removeListener('show',changed);window.removeListener('hide',changed);window.removeListener('closed',dispose);
        contents.removeListener('did-finish-load',loaded);
    };
    window.on('show',changed);window.on('hide',changed);window.on('closed',dispose);contents.on('did-finish-load',loaded);
    return dispose;
}
