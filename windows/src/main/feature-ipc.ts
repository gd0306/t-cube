import {FEATURE_CHANNELS as C} from '../shared/feature-channels';
import type {DesktopBridge} from '../shared/contracts';
import type {WindowRole} from './ipc';
interface Event {sender:{id:number;mainFrame:unknown};senderFrame:unknown}
export interface FeatureIPC {handle(channel:string,callback:(event:Event,value?:unknown)=>Promise<unknown>):void}
export const FEATURE_ROLES:Partial<Record<keyof DesktopBridge,WindowRole[]>>={
    showLibrary:['widget','settings','expanded','library'],getLibrary:['library'],saveSnippet:['library'],deleteSnippet:['library'],moveSnippet:['library'],useSnippetText:['library'],captureClipboard:['library'],
    getMaintenanceState:['settings'],exportBackup:['settings'],previewImportBackup:['settings'],confirmImportBackup:['settings'],createBackup:['settings'],repairLauncher:['settings'],revealBackups:['settings'],
    getLifecycleState:['settings'],setLoginEnabled:['settings'],setAutomaticUpdates:['settings'],checkForUpdates:['settings'],installUpdate:['settings'],openReleasePage:['settings'],getPerformanceSettings:['settings','widget'],setPerformanceSettings:['settings']
};
export function registerFeatureIPC(ipc:FeatureIPC,roles:(id:number)=>WindowRole|null,operations:Record<string,(value:unknown)=>unknown>,restoring:()=>boolean,report:(error:unknown)=>void):void{
    for(const[name,allowed]of Object.entries(FEATURE_ROLES)){
        const operation=operations[name];if(!operation)throw new Error(`Missing feature operation: ${name}`);
        const channel=C[name as keyof typeof C];
        ipc.handle(channel,async(event,value)=>{
            const role=roles(event.sender.id);
            if(!role||!allowed!.includes(role)||event.senderFrame!==event.sender.mainFrame)throw new Error('Not authorized');
            if(restoring())throw new Error('正在恢复备份，请稍候。');
            try{
                if(value!==undefined&&JSON.stringify(value).length>8*1024*1024)throw new Error('请求过大');
                return await operation(value);
            }catch(error){report(error);throw error;}
        });
    }
}
