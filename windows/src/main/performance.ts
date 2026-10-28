import {readFile} from 'node:fs/promises';
import {atomicWriteJSON} from '../core/atomic-json';
export interface PerformancePreferences {idlePowerSaving:boolean}
export class PerformanceStore {
    private queue: Promise<unknown> = Promise.resolve();
    constructor(readonly filePath:string){}
    async load():Promise<PerformancePreferences>{
        let value:unknown;
        try{value=JSON.parse(await readFile(this.filePath,'utf8'));}
        catch(error){if((error as NodeJS.ErrnoException).code==='ENOENT')return{idlePowerSaving:true};throw error;}
        if(!value||typeof value!=='object'||typeof(value as PerformancePreferences).idlePowerSaving!=='boolean')throw new Error('性能设置无效，原文件已保留');
        return{idlePowerSaving:(value as PerformancePreferences).idlePowerSaving};
    }
    save(idlePowerSaving:boolean):Promise<void>{
        const pending = this.queue.then(async () => {
            if(typeof idlePowerSaving!=='boolean')throw new Error('性能设置无效');
            await this.load();
            await atomicWriteJSON(this.filePath,{idlePowerSaving});
        });
        this.queue = pending.catch(() => undefined);
        return pending;
    }
}
