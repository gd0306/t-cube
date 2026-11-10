import type { ClipboardHistoryBridge, ClipboardHistoryState } from '../shared/clipboard-history';
export type QuickHistoryBridge = Pick<ClipboardHistoryBridge, 'getClipboardHistory' | 'setClipboardHistoryEnabled' | 'onClipboardHistoryChanged' | 'editClipboardHistoryEntry' | 'deleteClipboardHistoryEntry' | 'copyClipboardQuickEntry' | 'dismissClipboardQuick' | 'showClipboardHistory'>;
/** Compact copy-first view; the recorder and all mutations remain in the main process. */
export class ClipboardQuickPanel {
    private state: ClipboardHistoryState = {isEnabled:false,entries:[],totalBytes:0};
    private editing: {id:string;text:string} | undefined;
    private busy = false;
    private message = '';
    private version = 0;
    private unsubscribe: () => void;
    constructor(private readonly root: HTMLElement, private readonly bridge: QuickHistoryBridge) {
        root.className = 'quick-panel';
        this.unsubscribe = bridge.onClipboardHistoryChanged(state => { this.version++; this.update(state); });
        const version=this.version;
        void bridge.getClipboardHistory().then(state=>{if(version===this.version)this.update(state);}).catch(()=>{this.message='暂时无法读取历史，请关闭后重试。';this.render();});
        this.render();
    }
    dispose(): void {this.unsubscribe();this.root.replaceChildren();}
    private update(state: ClipboardHistoryState): void {
        this.state=state;
        if(this.editing&&state.entries.some(entry=>entry.id===this.editing!.id)) return;
        if(this.editing){this.editing=undefined;this.message='编辑的记录已删除或过期。';}
        this.render();
    }
    private button(label: string, action: () => void): HTMLButtonElement {
        const button=document.createElement('button');button.type='button';button.textContent=label;button.disabled=this.busy;
        button.onclick=()=>{if(!this.busy)action();};return button;
    }
    private async run(action: () => Promise<unknown>): Promise<void> {
        const editor=this.root.querySelector('textarea'),selection=editor?[editor.selectionStart,editor.selectionEnd] as const:undefined;
        let failed=false;
        if(this.busy)return;this.busy=true;this.message='';this.render();
        try{await action();}catch{failed=true;this.message=this.editing?'操作未完成：文字不能为空或包含空字符，每条最多 64 KiB、合计最多 2 MiB；记录也可能已删除。':'操作未完成，请重试；记录可能已删除或剪贴板暂不可用。';}
        finally{this.busy=false;this.render();if(failed&&this.editing){const input=this.root.querySelector('textarea');input?.focus();if(input&&selection)input.setSelectionRange(...selection);}}
    }
    private render(): void {
        this.root.replaceChildren();
        const header=document.createElement('header'),heading=document.createElement('h1');heading.textContent='剪贴板历史';
        const close=this.button('关闭',()=>{void this.bridge.dismissClipboardQuick();});header.append(heading,close);this.root.append(header);
        const note=document.createElement('p');note.className='quick-note';note.textContent=this.state.isEnabled?'单击复制 · 仅本次运行':'记录已暂停 · 仅本次运行';this.root.append(note);
        if(this.editing){this.renderEditor();return;}
        const list=document.createElement('div');list.className='quick-list';list.setAttribute('aria-label','历史快捷列表');
        const entries=[...this.state.entries,...(this.state.images??[])].sort((a,b)=>b.copiedAt-a.copiedAt);
        for(const entry of entries){
            const image='thumbnail'in entry,row=document.createElement('div');row.className='quick-row';
            const label=image?`${entry.width} × ${entry.height}`:entry.text.slice(0,180).replace(/\s+/g,' ');
            const copy=this.button(label,()=>{void this.run(()=>this.bridge.copyClipboardQuickEntry(entry.id));});
            copy.className='quick-copy';copy.setAttribute('aria-label',`${image?'复制图片':'复制文字'}：${label}`);
            if(image){const thumb=document.createElement('img');thumb.src=entry.thumbnail;thumb.alt='历史图片';thumb.className='quick-thumbnail';copy.prepend(thumb);}
            row.append(copy);
            const actions=document.createElement('div');actions.className='quick-actions';
            if(!image)actions.append(this.button('编辑文字',()=>{this.editing={id:entry.id,text:entry.text};this.render();this.root.querySelector('textarea')?.focus();}));
            actions.append(this.button(image?'删除图片':'删除文字',()=>{void this.run(()=>this.bridge.deleteClipboardHistoryEntry(entry.id));}));row.append(actions);list.append(row);
        }
        if(!entries.length){const empty=document.createElement('p');empty.className='quick-empty';empty.textContent=this.state.isEnabled?'等待下一次复制。启用前的内容不会加入历史。':'启用后才会记录新复制的文字和图片；退出应用即清空。';list.append(empty);}
        this.root.append(list);
        const footer=document.createElement('footer');
        if(!this.state.isEnabled)footer.append(this.button('启用记录',()=>{void this.run(()=>this.bridge.setClipboardHistoryEnabled(true));}));
        footer.append(this.button('完整历史管理',()=>{void this.run(async()=>{await this.bridge.showClipboardHistory();await this.bridge.dismissClipboardQuick();});}));this.root.append(footer);this.renderStatus();
    }
    private renderEditor(): void {
        const draft=this.editing!,label=document.createElement('label');label.textContent='编辑历史文字';
        const textarea=document.createElement('textarea');textarea.value=draft.text;textarea.setAttribute('aria-label','编辑历史文字');textarea.disabled=this.busy;
        textarea.oninput=()=>{draft.text=textarea.value;};label.append(textarea);this.root.append(label);
        const hint=document.createElement('p');hint.className='quick-note';hint.textContent='保存只修改历史，不会写入系统剪贴板。最多 64 KiB。';this.root.append(hint);
        const actions=document.createElement('footer');actions.append(this.button('保存',()=>{void this.run(async()=>{await this.bridge.editClipboardHistoryEntry(draft);this.editing=undefined;});}),this.button('取消',()=>{this.editing=undefined;this.message='';this.render();}));
        this.root.append(actions);this.renderStatus();
    }
    private renderStatus(): void {const status=document.createElement('p');status.className='quick-status';status.setAttribute('role','status');status.textContent=this.message||this.state.imageNotice||'';this.root.append(status);}
}
