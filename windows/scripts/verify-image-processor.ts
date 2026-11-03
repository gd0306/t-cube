import {build} from 'esbuild';
import {deflateSync} from 'node:zlib';
import {mkdir,writeFile} from 'node:fs/promises';
import {spawn} from 'node:child_process';
function crc32(bytes:Buffer):number{let crc=0xffffffff;for(const byte of bytes){crc^=byte;for(let i=0;i<8;i++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}return(crc^0xffffffff)>>>0;}
function chunk(type:string,bytes:Buffer):Buffer{const result=Buffer.alloc(bytes.length+12);result.writeUInt32BE(bytes.length);result.write(type,4);bytes.copy(result,8);result.writeUInt32BE(crc32(result.subarray(4,-4)),result.length-4);return result;}
await mkdir('.cache/smoke',{recursive:true});
const width=4000,height=4000,raw=Buffer.alloc((1+width*4)*height);
for(let y=0;y<height;y++){const start=y*(width*4+1);for(let x=0;x<width;x++){const p=start+1+x*4;raw[p]=x%256;raw[p+1]=y%256;raw[p+2]=128;raw[p+3]=255;}}
const header=Buffer.alloc(13);header.writeUInt32BE(width);header.writeUInt32BE(height,4);header[8]=8;header[9]=6;
await writeFile('.cache/smoke/owned-16mp.png',Buffer.concat([Buffer.from('89504e470d0a1a0a','hex'),chunk('IHDR',header),chunk('IDAT',deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]));
await build({entryPoints:['scripts/clipboard-image-worker-smoke.ts'],outfile:'.cache/smoke/image-worker-smoke.cjs',platform:'node',format:'cjs',bundle:true,external:['electron'],target:'node22'});
const executable=process.platform==='darwin'?'node_modules/electron/dist/Electron.app/Contents/MacOS/Electron':'node_modules/electron/dist/electron.exe';
const child=spawn(executable,['.cache/smoke/image-worker-smoke.cjs'],{stdio:'inherit',env:{...process.env,ELECTRON_DISABLE_SECURITY_WARNINGS:'true'}});
const timeout=setTimeout(()=>child.kill(),45000);
const code=await new Promise<number|null>((resolve,reject)=>{child.once('exit',resolve);child.once('error',reject);});clearTimeout(timeout);if(code!==0)throw Error(`Owned processor smoke exited ${code}`);
