import { clipboardTextTools } from './clipboard-text-tools';
import { CLIPBOARD_TEXT_ACTIONS, processClipboardText, clipboardTextNotice, type ClipboardTextAction } from '../shared/clipboard-text-processing';
import type { ClipboardHistoryBridge, ClipboardHistoryState } from '../shared/clipboard-history';
export type QuickHistoryBridge = Pick<ClipboardHistoryBridge, 'getClipboardHistory' | 'setClipboardHistoryEnabled' | 'onClipboardHistoryChanged' | 'editClipboardHistoryEntry' | 'deleteClipboardHistoryEntry' | 'copyClipboardQuickEntry' | 'dismissClipboardQuick' | 'showClipboardHistory'>;
/** Compact copy-first view; the recorder and all mutations remain in the main process. */
export class ClipboardQuickPanel {
    private state: ClipboardHistoryState = {isEnabled:false,entries:[],totalBytes:0};
    private editing: {id:string;text:string} | undefined;
    private processing: {id: string; action: ClipboardTextAction; source: string; text: string; editing: boolean} | undefined;
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
        if (this.processing && state.entries.find(entry => entry.id === this.processing!.id)?.text !== this.processing.source) {
            this.processing = undefined; this.message = '原记录已修改或删除，请重新选择处理。';
        }
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
        finally{this.busy=false;this.render();if(failed&&(this.editing||this.processing?.editing)){const input=this.root.querySelector('textarea');input?.focus();if(input&&selection)input.setSelectionRange(...selection);}}
    }
    private render(): void {
        this.root.replaceChildren();
        const header=document.createElement('header'),heading=document.createElement('h1');heading.textContent='剪贴板历史';
        const close=this.button('关闭',()=>{void this.bridge.dismissClipboardQuick();});header.append(heading,close);this.root.append(header);
        const note=document.createElement('p');note.className='quick-note';note.textContent=this.state.isEnabled?'单击复制 · 拖动标题移动 · 退出清空':'记录已暂停 · 拖动标题移动 · 退出清空';this.root.append(note);
        if(this.processing){this.renderProcessing();return;}
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
            if(!image)actions.append(clipboardTextTools(this.busy, action => this.beginProcessing(entry.id, action)), this.button('编辑文字',()=>{this.editing={id:entry.id,text:entry.text};this.render();this.root.querySelector('textarea')?.focus();}));
            actions.append(this.button(image?'删除图片':'删除文字',()=>{void this.run(()=>this.bridge.deleteClipboardHistoryEntry(entry.id));}));row.append(actions);list.append(row);
        }
        if(!entries.length){const empty=document.createElement('p');empty.className='quick-empty';empty.textContent=this.state.isEnabled?'等待下一次复制。启用前的内容不会加入历史。':'启用后才会记录新复制的文字和图片；退出应用即清空。';list.append(empty);}
        this.root.append(list);
        const footer=document.createElement('footer');
        if(!this.state.isEnabled)footer.append(this.button('启用记录',()=>{void this.run(()=>this.bridge.setClipboardHistoryEnabled(true));}));
        footer.append(this.button('完整历史管理',()=>{void this.run(async()=>{await this.bridge.showClipboardHistory();await this.bridge.dismissClipboardQuick();});}));this.root.append(footer);this.renderStatus();
    }
    private beginProcessing(id: string, action: ClipboardTextAction): void {
        const entry = this.state.entries.find(entry => entry.id === id);
        if (!entry) return;
        this.processing = undefined;
        try {
            const text = processClipboardText(entry.text, action);
            this.processing = {id, action, source: entry.text, text, editing: false};
            this.message = clipboardTextNotice(entry.text, action, text) ?? '';
        } catch (error) { this.message = (error as Error).message; }
        this.render();
    }
    resetForShow(): void {
        this.processing = undefined; this.editing = undefined; this.message = ''; this.render();
    }
    handleEscape(): boolean {
        if (!this.processing) return false;
        this.processing = undefined; this.message = ''; this.render(); return true;
    }
    private renderProcessing(): void {
        const draft = this.processing!, heading = document.createElement('h2');
        heading.textContent = CLIPBOARD_TEXT_ACTIONS[draft.action] + ' · 预览'; this.root.append(heading);
        let valid = true;
        try { processClipboardText(draft.text, 'original'); }
        catch (error) { valid = false; this.message = (error as Error).message; }
        if (draft.editing) {
            const input = document.createElement('textarea'); input.value = draft.text; input.disabled = this.busy;
            input.setAttribute('aria-label', '编辑处理结果');
            input.oninput = () => {
                draft.text = input.value;
                let issue = '';
                try { processClipboardText(draft.text, 'original'); } catch (error) { issue = (error as Error).message; }
                this.root.querySelectorAll<HTMLButtonElement>('[data-processing-output]').forEach(button => { button.disabled = this.busy || Boolean(issue); });
                this.root.querySelector<HTMLElement>('[role="status"]')!.textContent = issue;
            };
            this.root.append(input);
        } else {
            const preview = document.createElement('pre'); preview.className = 'quick-processing-preview'; preview.textContent = draft.text;
            preview.setAttribute('aria-label', valid ? '处理结果预览' : '原文（处理失败）'); this.root.append(preview);
        }
        const hint = document.createElement('p'); hint.className = 'quick-note';
        hint.textContent = '复制不改动历史；保存仅修改本条记录，不写入剪贴板。最多 64 KiB。'; this.root.append(hint);
        const actions = document.createElement('footer');
        const copy = this.button('复制处理结果', () => { void this.run(async () => {
            await this.bridge.copyClipboardQuickEntry(draft.id, draft.action, {sourceText: draft.source, ...(draft.editing ? {text: draft.text} : {})});
            this.processing = undefined;
        }); });
        copy.disabled ||= !valid; copy.dataset.processingOutput = '';
        const edit = draft.editing ? this.button('保存到本条记录', () => { void this.run(async () => {
            await this.bridge.editClipboardHistoryEntry({id: draft.id, text: draft.text, expectedText: draft.source});
            this.processing = undefined; this.message = '已修改本条记录；系统剪贴板保持原样。';
        }); }) : this.button('编辑结果', () => { draft.editing = true; this.message = ''; this.render(); this.root.querySelector('textarea')?.focus(); });
        if (draft.editing) { edit.disabled ||= !valid; edit.dataset.processingOutput = ''; }
        actions.append(copy, edit, this.button('取消处理', () => { this.processing = undefined; this.message = ''; this.render(); }));
        this.root.append(actions); this.renderStatus();
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
