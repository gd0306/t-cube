import {CLIPBOARD_IMAGE_LIMITS as LIMITS} from '../shared/clipboard-history';
interface Request {token:string;mode:'normalize'|'preview';bytes:Uint8Array}
interface ProcessorBridge {onRequest(callback:(request:Request)=>void):void;complete(value:unknown):void}
const bridge=(window as unknown as {tcubeImageProcessor:ProcessorBridge}).tcubeImageProcessor;
let busy=false;
const dataURL=(blob:Blob)=>new Promise<string>((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result as string);reader.onerror=reject;reader.readAsDataURL(blob);});
async function render(bitmap:ImageBitmap,side:number):Promise<Blob>{
    const factor=Math.min(1,side/bitmap.width,side/bitmap.height);
    const canvas=new OffscreenCanvas(Math.max(1,Math.round(bitmap.width*factor)),Math.max(1,Math.round(bitmap.height*factor)));
    try{const context=canvas.getContext('2d');if(!context)throw Error('Canvas unavailable');context.drawImage(bitmap,0,0,canvas.width,canvas.height);return await canvas.convertToBlob({type:'image/png'});}
    finally{canvas.width=canvas.height=1;}
}
bridge.onRequest(request=>{
    if(busy)return;
    busy=true;
    void(async()=>{
        let bitmap:ImageBitmap|undefined;
        try{
            if(!request || typeof request.token!=='string' || !['normalize','preview'].includes(request.mode) || !(request.bytes instanceof Uint8Array) || request.bytes.length>LIMITS.itemBytes)throw Error('Invalid job');
            bitmap=await createImageBitmap(new Blob([Uint8Array.from(request.bytes)]));
            if(bitmap.width<1 || bitmap.height<1 || bitmap.width*bitmap.height>LIMITS.pixels)throw Error('Image dimensions');
            if(request.mode==='preview')bridge.complete({token:request.token,preview:await dataURL(await render(bitmap,LIMITS.previewSide))});
            else{
                const png=await render(bitmap,Math.max(bitmap.width,bitmap.height));
                if(png.size>LIMITS.itemBytes)throw Error('Encoded image too large');
                const thumbnail=await dataURL(await render(bitmap,LIMITS.thumbnailSide));
                bridge.complete({token:request.token,png:new Uint8Array(await png.arrayBuffer()),width:bitmap.width,height:bitmap.height,thumbnail});
            }
        }catch{bridge.complete({token:request.token,error:'Image unavailable or over limits'});}
        finally{bitmap?.close();busy=false;}
    })();
});
