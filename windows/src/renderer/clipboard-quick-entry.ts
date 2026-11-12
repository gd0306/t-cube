import { ClipboardQuickPanel } from './clipboard-quick';
const panel = new ClipboardQuickPanel(document.querySelector('main')!,window.tcube);
const stopShown=window.tcube.onClipboardQuickShown(()=>panel.resetForShow());
window.addEventListener('unload',()=>{stopShown();panel.dispose();});
window.addEventListener('keydown',event=>{if(event.key==='Escape'){event.preventDefault();if(!panel.handleEscape())void window.tcube.dismissClipboardQuick();}});
