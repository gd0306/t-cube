import { ClipboardQuickPanel } from './clipboard-quick';
const panel = new ClipboardQuickPanel(document.querySelector('main')!,window.tcube);
window.addEventListener('unload',()=>panel.dispose());
window.addEventListener('keydown',event=>{if(event.key==='Escape'){event.preventDefault();void window.tcube.dismissClipboardQuick();}});
