import koffi from 'koffi';

/** The packet is inspected synchronously and discarded; no key history is retained. */
export function rawInputInterferes(packet: Buffer, headerSize: number): boolean {
    if (packet.length < headerSize + 16) return false;
    const type = packet.readUInt32LE(0);
    if (type === 0) return packet.readUInt16LE(headerSize + 4) !== 0; // Mouse buttons/wheels, never motion.
    if (type === 1) return ![0x11, 0xa2, 0xa3].includes(packet.readUInt16LE(headerSize + 6));
    return false;
}
export function rawControlReleased(packet: Buffer, headerSize: number): boolean {
    return packet.length >= headerSize + 16 && packet.readUInt32LE(0) === 1
        && [0x11,0xa2,0xa3].includes(packet.readUInt16LE(headerSize + 6)) && Boolean(packet.readUInt16LE(headerSize + 2) & 1);
}
export function otherInputHeld(read: (key: number) => number): boolean {
    for (let key = 1; key < 255; key++) {
        if (key !== 0x11 && key !== 0xa2 && key !== 0xa3 && (read(key) & 0x8000)) return true;
    }
    return false;
}
interface InputWindow {
    isDestroyed(): boolean;
    getNativeWindowHandle(): Buffer;
    hookWindowMessage(message: number, callback: (wParam: Buffer, lParam: Buffer) => void): void;
    unhookWindowMessage(message: number): void;
}
/** Raw Input supplements polling with brief shortcuts and wheels, without suppressing legacy input or installing hooks. */
export function observeControlInterference(window: InputWindow, interrupt: () => void, released: () => void = () => {}): {available: boolean; otherHeld(): boolean; baseline(): void; dispose(): void} {
    const inactive = {available:false,otherHeld:()=>false,baseline:()=>{},dispose:()=>{}};
    if (process.platform !== 'win32') return inactive;
    const library = koffi.load('user32.dll');
    const device = koffi.struct({page:'uint16_t',usage:'uint16_t',flags:'uint32_t',target:'uintptr_t'});
    const register = library.func('int __stdcall RegisterRawInputDevices(const void *devices, uint32_t count, uint32_t size)');
    const data = library.func('uint32_t __stdcall GetRawInputData(uintptr_t input, uint32_t command, _Out_ void *data, _Inout_ uint32_t *size, uint32_t headerSize)');
    const key = library.func('int16_t __stdcall GetAsyncKeyState(int key)');
    const pointerSize = koffi.sizeof('void *'), headerSize = pointerSize === 8 ? 24 : 16;
    const pointer = (buffer: Buffer) => pointerSize === 8 ? buffer.readBigUInt64LE() : BigInt(buffer.readUInt32LE());
    const devices = (flags: number, target: bigint) => {
        const bytes = Buffer.alloc(koffi.sizeof(device)*2);
        [2,6].forEach((usage,index) => koffi.encode(bytes.subarray(index*koffi.sizeof(device)),device,{page:1,usage,flags,target}));
        return bytes;
    };
    if (!register(devices(0x100,pointer(window.getNativeWindowHandle())),2,koffi.sizeof(device))) return inactive;
    let disposed = false;
    let leftControl=Boolean(key(0xa2)&0x8000),rightControl=Boolean(key(0xa3)&0x8000);
    const bytes=Buffer.alloc(64),size=[bytes.length];
    window.hookWindowMessage(0xff, (_wParam,lParam) => {
        if (disposed || (!leftControl&&!rightControl&&!(key(0x11)&0x8000))) return;
        try {
            size[0]=bytes.length;
            const count = data(pointer(lParam),0x10000003,bytes,size,headerSize);
            if (count === 0xffffffff || count > bytes.length || count < headerSize) { interrupt(); return; }
            const packet=bytes.subarray(0,count);
            if(packet.length>=headerSize+16&&packet.readUInt32LE(0)===1){
                const virtualKey=packet.readUInt16LE(headerSize+6),flags=packet.readUInt16LE(headerSize+2);
                if([0x11,0xa2,0xa3].includes(virtualKey)){
                    const right=virtualKey===0xa3||(virtualKey===0x11&&Boolean(flags&2));
                    if(right)rightControl=!Boolean(flags&1);else leftControl=!Boolean(flags&1);
                    if(rawControlReleased(packet,headerSize)&&!leftControl&&!rightControl)released();
                    return;
                }
            }
            if ((leftControl||rightControl||Boolean(key(0x11)&0x8000))&&rawInputInterferes(packet,headerSize)) interrupt();
        } catch { interrupt(); } finally { bytes.fill(0); } // Never retain a keyboard packet between callbacks.

    });
    return {available:true,otherHeld:()=>otherInputHeld(key),baseline:()=>{leftControl=Boolean(key(0xa2)&0x8000);rightControl=Boolean(key(0xa3)&0x8000);},dispose:()=>{
        if (disposed) return; disposed=true;
        if(!window.isDestroyed())window.unhookWindowMessage(0xff);
        register(devices(1,0n),2,koffi.sizeof(device));
    }};
}
