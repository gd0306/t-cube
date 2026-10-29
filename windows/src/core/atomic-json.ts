import {mkdir,open,rename,unlink} from 'node:fs/promises';
import {dirname} from 'node:path';
import {randomUUID} from 'node:crypto';
export async function atomicWriteJSON(file:string,value:unknown):Promise<void>{
    await mkdir(dirname(file),{recursive:true});
    const temporary=`${file}.${randomUUID()}.tmp`;
    try{
        const handle=await open(temporary,'wx',0o600);
        try{await handle.writeFile(JSON.stringify(value,null,2)+'\n','utf8');await handle.sync();}finally{await handle.close();}
        await rename(temporary,file);
    }finally{await unlink(temporary).catch(error=>{if(error.code!=='ENOENT')throw error;});}
}
