import { ClipboardHistoryRecorder, clipboardHistoryOperations } from './clipboard-history';
import { readHistoryClipboardItems } from './history-clipboard-reader';
import { clipboardHistoryFormatsAllowed } from '../native/clipboard-history';
import {app,BrowserWindow,clipboard,dialog,globalShortcut,ipcMain,screen} from 'electron';
import path from 'node:path';
import type {LauncherHost} from './application';
import type {WindowRole} from './ipc';
import {SnippetStore} from '../core/snippet-store';
import {validateSnippetText} from '../core/snippet-library';
import {ContentLibraryService} from './content-library';
import {capturePasteTarget,pasteToTarget,clipboardSequenceNumber,type PasteTarget} from '../native/paste-target';
import {MaintenanceService} from './maintenance';
import {createLifecycleService,type LifecycleController} from './lifecycle';
import {PerformanceStore} from './performance';
import {FEATURE_CHANNELS as C} from '../shared/feature-channels';
import {registerFeatureIPC} from './feature-ipc';
import type {TextSnippet} from '../shared/productivity';
import {FACES,type Face} from '../shared/contracts';
const record=(value:unknown):Record<string,unknown>=>{if(!value||typeof value!=='object'||Array.isArray(value))throw new Error('Invalid request');return value as Record<string,unknown>;};
const string=(value:unknown,max=128):string=>{if(typeof value!=='string'||!value.length||value.length>max)throw new Error('Invalid text');return value;};
const boolean=(value:unknown):boolean=>{if(typeof value!=='boolean')throw new Error('Invalid preference');return value;};
export interface OfficeOptions {whenLauncherOperationsIdle:()=>Promise<void>;host:LauncherHost;directory:string;rendererPath:string;createLibraryWindow:()=>BrowserWindow;role:(id:number)=>WindowRole|null;historyChanged?:()=>void}
export class OfficeServices {
    libraryWindow:BrowserWindow|null=null;
    readonly clipboardHistory: ClipboardHistoryRecorder;
    readonly library:ContentLibraryService;
    readonly maintenance:MaintenanceService;
    readonly performance:PerformanceStore;
    lifecycle!:LifecycleController;
    private target:PasteTarget|null=null;
    private restoreGate=false;
    private quitting=false;
    setQuitting(value:boolean){this.quitting=value;}
    private load:Promise<void>|null=null;
    private pasteGeneration=0;
    private shortcutRegistered=false;
    private pending = new Set<Promise<unknown>>();
    async whenIdle():Promise<void>{while(this.pending.size)await Promise.allSettled([...this.pending]);}
    get isRestoring(){return this.quitting||this.restoreGate||this.maintenance.isRestoring;}
    constructor(private readonly options:OfficeOptions){
        this.clipboardHistory = new ClipboardHistoryRecorder({
            sequence: clipboardSequenceNumber,
            read: async isCurrent => {
                const allowed = () => isCurrent() && clipboardHistoryFormatsAllowed();
                if (!allowed()) return null;
                const items = await clipboard.read();
                if (!allowed()) return null;
                return readHistoryClipboardItems(items, allowed);
            },
        }, state => {
            this.libraryWindow?.webContents.send(C.clipboardHistoryChanged, state);
            this.options.historyChanged?.();
        });
        const configurationPath=path.join(options.directory,'configuration.json'),libraryPath=path.join(options.directory,'content-library.json');
        this.library=new ContentLibraryService(new SnippetStore(libraryPath));
        this.performance=new PerformanceStore(path.join(options.directory,'performance-preferences.json'));
        this.maintenance=new MaintenanceService({configurationPath,libraryPath,getConfiguration:()=>options.host.snapshot.state.configuration,
            afterRestore:async configuration=>{await options.host.applyImportedConfiguration(configuration);await this.library.reload();this.libraryWindow?.webContents.send(C.libraryChanged);},
            repairLauncher:async request=>{
                const item=options.host.snapshot.state.configuration.groups[request.face].slots[request.slot];if(!item)throw new Error('入口已变更');
                if(item.kind==='website'||item.kind==='systemSettings')throw new Error('请在应用分组中重新选择网站或系统设置。');
                const result=await dialog.showOpenDialog({title:`重新选择「${item.name}」`,properties:[item.kind==='folder'?'openDirectory':'openFile'],filters:item.kind==='application'?[{name:'应用程序或快捷方式',extensions:['exe','lnk']}]:undefined});
                if(!result.canceled&&result.filePaths[0])await options.host.repairLauncher(request,result.filePaths[0],item.id);
            }});
    }
    async start(){
        this.lifecycle=await createLifecycleService();await this.lifecycle.start();
        try{this.options.host.setIdlePowerSaving((await this.performance.load()).idlePowerSaving);}catch(error){this.options.host.reportError(error);}
        this.shortcutRegistered=globalShortcut.register('CommandOrControl+Shift+Space',()=>{void this.showLibrary().catch(error=>this.options.host.reportError(error));});
        if(!this.shortcutRegistered)this.options.host.reportError('常用内容快捷键已被占用，可从托盘或立方体打开。');
        this.registerIPC();
    }
    async showLibrary(text?:string){
        if(text!==undefined)validateSnippetText(text);
        this.pasteGeneration++;
        if(!this.libraryWindow?.isVisible())this.target=capturePasteTarget();
        if(!this.libraryWindow){
            this.libraryWindow=this.options.createLibraryWindow();
            this.libraryWindow.once('closed',()=>{this.libraryWindow=null;this.load=null;});
            this.load=this.libraryWindow.loadFile(this.options.rendererPath);
            this.libraryWindow.webContents.on('before-input-event',(_event,input)=>{if(input.type==='keyDown'&&input.key==='Escape')this.libraryWindow?.hide();});
        }
        await this.load;
        const window=this.libraryWindow,display=screen.getDisplayNearestPoint(screen.getCursorScreenPoint()).workArea,point=screen.getCursorScreenPoint(),bounds=window.getBounds();
        window.setPosition(Math.round(Math.max(display.x,Math.min(point.x-bounds.width/2,display.x+display.width-bounds.width))),Math.round(Math.max(display.y,Math.min(point.y-bounds.height/2,display.y+display.height-bounds.height))));
        window.show();window.focus();
        if(text!==undefined)window.webContents.send(C.libraryCapture,text);
    }
    async showClipboardHistory() {
        await this.showLibrary();
        this.libraryWindow?.webContents.send(C.showClipboardHistoryMode);
    }
    private async use(value:unknown){
        const request=record(value),text=string(request.text,262144),paste=boolean(request.paste);validateSnippetText(text);
        const generation=++this.pasteGeneration;
        await this.clipboardHistory.performOwnWrite(() => clipboard.writeText(text));
        const sequence = clipboardSequenceNumber();
        if(!paste)return{status:'已复制。'};
        this.libraryWindow?.hide();
        const completed=await pasteToTarget(this.target,()=>generation===this.pasteGeneration&&sequence!==null&&clipboardSequenceNumber()===sequence);
        if(!completed){this.libraryWindow?.show();this.libraryWindow?.focus();}
        return{status:completed?'已粘贴到原输入位置。':'已复制。原输入位置不可用，请手动粘贴；可先点中目标输入框，再用快捷键呼出。'};
    }
    private registerIPC(){
        const operations:Record<string,(value:unknown)=>unknown>={
            ...clipboardHistoryOperations(this.clipboardHistory, request => this.use(request)),
            showClipboardHistory: value => { if (value !== undefined) throw new Error('Invalid history request'); return this.showClipboardHistory(); },
            showLibrary:value=>this.showLibrary(value===undefined?undefined:string(value,262144)),getLibrary:()=>this.library.get(),
            saveSnippet:value=>this.library.save(value as TextSnippet),deleteSnippet:value=>this.library.delete(string(value)),
            moveSnippet:value=>{const v=record(value);return this.library.move({id:string(v.id),neighborId:string(v.neighborId)});},
            useSnippetText:value=>this.use(value),captureClipboard:async()=>{const text=await clipboard.readText();validateSnippetText(text);return text;},
            getMaintenanceState:()=>this.maintenance.getMaintenanceState(),exportBackup:()=>this.maintenance.exportBackup(),
            previewImportBackup:value=>this.maintenance.previewImportBackup(value===undefined?undefined:string(value)),
            confirmImportBackup:async value=>{
                const token=string(value);if(this.options.host.snapshot.state.interactionActive)throw new Error('请先松开立方体，再恢复备份。');
                this.restoreGate=true;
                try{await this.options.whenLauncherOperationsIdle();await this.options.host.whenIdle({includeLaunches:false});return await this.maintenance.confirmImportBackup(token);}finally{this.restoreGate=false;}
            },createBackup:()=>this.maintenance.createBackup(),repairLauncher:value=>{const v=record(value);if(!FACES.includes(v.face as Face)||!Number.isInteger(v.slot)||(v.slot as number)<0||(v.slot as number)>3)throw new Error('Invalid launcher');return this.maintenance.repairLauncher({face:v.face as Face,slot:v.slot as number});},revealBackups:()=>this.maintenance.revealBackups(),
            getLifecycleState:()=>this.lifecycle.getLifecycleState(),setLoginEnabled:value=>this.lifecycle.setLoginEnabled(boolean(value)),setAutomaticUpdates:value=>this.lifecycle.setAutomaticUpdates(boolean(value)),checkForUpdates:()=>this.lifecycle.checkForUpdates(),installUpdate:()=>this.lifecycle.installUpdate(),openReleasePage:()=>this.lifecycle.openReleasePage(),
            getPerformanceSettings:()=>this.performance.load(),setPerformanceSettings:async value=>{const enabled=boolean(value);await this.performance.save(enabled);this.options.host.setIdlePowerSaving(enabled);}
        };
        const tracked = Object.fromEntries(Object.entries(operations).map(([name,operation]) => [name,(value:unknown) => {
            const pending = Promise.resolve().then(() => operation(value));
            this.pending.add(pending);
            void pending.then(() => this.pending.delete(pending), () => this.pending.delete(pending));
            return pending;
        }]));
        registerFeatureIPC(ipcMain,this.options.role,tracked,()=>this.isRestoring,error=>this.options.host.reportError(error));
    }
    dispose(){this.clipboardHistory.dispose();this.pasteGeneration++;if(this.shortcutRegistered)globalShortcut.unregister('CommandOrControl+Shift+Space');this.lifecycle?.dispose();}
}
