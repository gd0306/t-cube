import {build} from 'esbuild';
import {spawn} from 'node:child_process';
await build({entryPoints:['scripts/edge-glass-window-smoke.ts'],outfile:'.cache/smoke/edge-glass-window-smoke.cjs',platform:'node',format:'cjs',bundle:true,external:['electron'],target:'node22'});
const executable=process.platform==='darwin'?'node_modules/electron/dist/Electron.app/Contents/MacOS/Electron':'node_modules/electron/dist/electron.exe';
const child=spawn(executable,['.cache/smoke/edge-glass-window-smoke.cjs'],{stdio:'inherit',env:{...process.env,ELECTRON_DISABLE_SECURITY_WARNINGS:'true'}});
const timeout=setTimeout(()=>child.kill(),30000);
const code=await new Promise<number|null>((resolve,reject)=>{child.once('exit',resolve);child.once('error',reject);});clearTimeout(timeout);if(code!==0)throw Error(`Owned edge lifecycle smoke exited ${code}`);
