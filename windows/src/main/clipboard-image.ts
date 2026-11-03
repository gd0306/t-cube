import { BrowserWindow, ipcMain } from 'electron';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { imageDimensions, pngDimensions, boundedPNGDataURL } from '../core/clipboard-image';
import type { HistoryImage } from '../core/clipboard-history';
import { CLIPBOARD_IMAGE_LIMITS as LIMITS } from '../shared/clipboard-history';
interface Job {token:string; mode:'normalize'|'preview'; bytes:Buffer; current:()=>boolean; resolve:(value:HistoryImage|string|null)=>void}
const REQUEST='tcube:private-image-request', REPLY='tcube:private-image-reply';
/** One lazy sandbox renderer does codecs away from Electron main. At most one active, newest capture and newest preview. */
export class ClipboardImageProcessor {
    private window:BrowserWindow|null=null;
    private active:Job|undefined;
    private pendingNormalize:Job|undefined;
    private pendingPreview:Job|undefined;
    private timeout:NodeJS.Timeout|undefined;
    private idle:NodeJS.Timeout|undefined;
    private disposed=false;
    private readonly reply=(event:Electron.IpcMainEvent,value:unknown)=>{
        const job=this.active, window=this.window;
        if(!job || !window || event.sender!==window.webContents || event.senderFrame!==window.webContents.mainFrame || !value || typeof value!=='object')return;
        const reply=value as Record<string,unknown>;
        if(reply.token!==job.token)return;
        let result:HistoryImage|string|null=null;
        if(job.current() && reply.error===undefined){
            if(job.mode==='preview' && boundedPNGDataURL(reply.preview,LIMITS.previewSide,6*1024*1024))result=reply.preview;
            if(job.mode==='normalize' && reply.png instanceof Uint8Array && reply.png.byteLength<=LIMITS.itemBytes && boundedPNGDataURL(reply.thumbnail,LIMITS.thumbnailSide,128*1024)){
                const png=Buffer.from(reply.png),size=pngDimensions(png);
                if(size && size.width===reply.width && size.height===reply.height)result={png,...size,thumbnail:reply.thumbnail};
            }
        }
        this.finish(result);
    };
    constructor(private readonly directory:string){ipcMain.on(REPLY,this.reply);}
    normalize(bytes:Buffer,current:()=>boolean):Promise<HistoryImage|null>{return this.enqueue('normalize',bytes,current) as Promise<HistoryImage|null>;}
    preview(image:HistoryImage,current:()=>boolean):Promise<string|null>{return this.enqueue('preview',image.png,current) as Promise<string|null>;}
    private enqueue(mode:Job['mode'],bytes:Buffer,current:()=>boolean):Promise<HistoryImage|string|null>{
        if(this.disposed || !current() || !imageDimensions(bytes))return Promise.resolve(null);
        if(this.idle){clearTimeout(this.idle);this.idle=undefined;}
        return new Promise(resolve=>{
            const job={token:randomUUID(),mode,bytes,current,resolve};
            if(this.active){if(mode==='normalize'){this.pendingNormalize?.resolve(null);this.pendingNormalize=job;}else{this.pendingPreview?.resolve(null);this.pendingPreview=job;}}
            else void this.run(job);
        });
    }
    private async run(job:Job):Promise<void>{
        if(!job.current() || this.disposed){job.resolve(null);if(!this.disposed)this.finish(null);return;}
        this.active=job;
        this.timeout=setTimeout(()=>this.cancel(),15000);this.timeout.unref();
        try{
            if(!this.window){
                const window=new BrowserWindow({show:false,width:1,height:1,skipTaskbar:true,webPreferences:{preload:path.join(path.dirname(this.directory),'image-processor-preload.cjs'),sandbox:true,contextIsolation:true,nodeIntegration:false,backgroundThrottling:false}});
                this.window=window;
                window.webContents.setWindowOpenHandler(()=>({action:'deny'}));
                window.webContents.on('will-navigate',event=>event.preventDefault());
                window.webContents.on('will-attach-webview',event=>event.preventDefault());
                window.webContents.session.setPermissionRequestHandler((_contents,_permission,callback)=>callback(false));
                window.webContents.once('render-process-gone',()=>{if(this.window===window)this.cancel();});
                await window.loadFile(path.join(this.directory,'image-processor.html'));
            }
            if(this.active!==job || !job.current() || !this.window){if(this.active===job)this.finish(null);return;}
            this.window.webContents.send(REQUEST,{token:job.token,mode:job.mode,bytes:job.bytes});
        }catch{if(this.active===job)this.cancel();}
    }
    private finish(value:HistoryImage|string|null):void{
        if(this.timeout)clearTimeout(this.timeout);this.timeout=undefined;
        const active=this.active;this.active=undefined;active?.resolve(value);
        const pending=this.pendingNormalize??this.pendingPreview;
        if(this.pendingNormalize)this.pendingNormalize=undefined;else this.pendingPreview=undefined;
        if(pending)void this.run(pending);
        else if(!this.disposed){this.idle=setTimeout(()=>this.cancel(),10000);this.idle.unref();}
    }
    /** Pause, clear and shutdown release in-flight source bytes and the idle renderer immediately. */
    cancel():void{
        if(this.timeout)clearTimeout(this.timeout);if(this.idle)clearTimeout(this.idle);this.timeout=this.idle=undefined;
        const active=this.active,capture=this.pendingNormalize,preview=this.pendingPreview;this.active=this.pendingNormalize=this.pendingPreview=undefined;
        active?.resolve(null);capture?.resolve(null);preview?.resolve(null);
        const window=this.window;this.window=null;if(window && !window.isDestroyed())window.destroy();
    }
    dispose():void{this.disposed=true;this.cancel();ipcMain.removeListener(REPLY,this.reply);}
}
