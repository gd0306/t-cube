import { clipboardTextTools } from './clipboard-text-tools';
import { CLIPBOARD_TEXT_ACTIONS, processClipboardText, clipboardTextNotice, type ClipboardTextAction } from '../shared/clipboard-text-processing';
import type { DesktopBridge } from '../shared/contracts';
import { mergeHistoryText, type ClipboardHistoryState, type ClipboardMergeRequest } from '../shared/clipboard-history';

/** Separate DOM keeps ordinary snippet and template drafts intact when changing modes. */
export class ClipboardHistoryPanel {
    private state: ClipboardHistoryState = { isEnabled: false, entries: [], totalBytes: 0 };
    private selectedId: string | undefined;
    private selected = new Set<string>();
    private category: 'text' | 'images' = 'text';
    private trimLines = false;
    private collapseBlankLines = false;
    private list = document.createElement('div');
    private detail = document.createElement('section');
    private search = document.createElement('input');
    private toggle = document.createElement('button');
    private clear = document.createElement('button');
    private count = document.createElement('span');
    private status = document.createElement('p');
    private processing: {id: string; action: ClipboardTextAction; source: string; text: string; editing: boolean} | undefined;
    private busy = false;
    private editDraft: {id:string;text:string}|undefined;
    private enabledBefore = false;
    private version = 0;
    private previewVersion = 0;
    private imagePreview: {id: string; pending: Promise<string | null>} | undefined;
    private unsubscribe: () => void;
    constructor(private readonly root: HTMLElement, private readonly bridge: DesktopBridge, private readonly saveDraft: (text: string) => void) {
        root.className = 'clipboard-history';
        const privacy = document.createElement('p'); privacy.className = 'history-privacy';
        privacy.textContent = '每次启动自动记录新复制的文字和图片；暂停后停止读取。启用或恢复时从下一次复制开始，之前的剪贴板内容不会补录。历史仅保存在本次运行的内存中，退出即清空，不进入备份。文字最多 100 条，每条 64 KiB、合计 2 MiB；图片最多 10 张，每张 8 MiB、合计 32 MiB，最大 1600 万像素。会尽力跳过应用标记的敏感内容和文件，请按需暂停。';
        const controls = document.createElement('div'); controls.className = 'history-controls';
        this.toggle.type = this.clear.type = 'button'; this.clear.textContent = '清空历史';
        this.toggle.onclick = () => { void this.run(() => bridge.setClipboardHistoryEnabled(!this.state.isEnabled)); };
        this.clear.onclick = () => { if (window.confirm('清空本次运行的全部剪贴板历史？')) void this.run(() => bridge.clearClipboardHistory()); };
        controls.append(this.toggle, this.clear, this.count);
        const tabs = document.createElement('div'); tabs.className = 'history-controls'; tabs.setAttribute('aria-label', '历史分类');
        for (const [label, category] of [['文字', 'text'], ['图片', 'images']] as const) {
            const button = this.button(label, () => { this.category = category; this.processing = undefined; this.imagePreview = undefined; this.selected.clear(); this.selectedId = undefined; this.search.value = ''; this.render(); });
            button.dataset.category = category; tabs.append(button);
        }
        const columns = document.createElement('div'); columns.className = 'history-columns';
        const aside = document.createElement('aside');
        this.search.type = 'search'; this.search.placeholder = '搜索剪贴板历史'; this.search.setAttribute('aria-label', '搜索剪贴板历史');
        this.search.oninput = () => { this.processing = undefined; this.selected.clear(); this.selectedId = undefined; this.render(); };
        this.list.className = 'history-list'; this.list.setAttribute('aria-label', '剪贴板历史列表');
        this.detail.className = 'history-detail'; this.detail.setAttribute('aria-label', '历史详情');
        aside.append(this.search, this.list); columns.append(aside, this.detail);
        this.status.setAttribute('role', 'status'); this.status.className = 'history-status';
        root.append(privacy, controls, tabs, columns, this.status);
        this.unsubscribe = bridge.onClipboardHistoryChanged(state => { this.version++; this.update(state); });
        const version = this.version;
        void bridge.getClipboardHistory().then(state => { if (this.version === version) this.update(state); }).catch(() => { this.status.textContent = '暂时无法读取历史状态。'; });
        this.render();
    }
    dispose(): void { this.unsubscribe(); this.previewVersion++; this.imagePreview = undefined; this.detail.replaceChildren(); }
    private update(state: ClipboardHistoryState): void { if(state.imageNotice)this.status.textContent=state.imageNotice;else if(this.state.imageNotice)this.status.textContent=''; if (this.imagePreview && !state.images?.some(image => image.id === this.imagePreview!.id)) this.imagePreview = undefined; this.state = state; this.enabledBefore ||= state.isEnabled;
        if (this.processing && state.entries.find(entry => entry.id === this.processing!.id)?.text !== this.processing.source) {
            this.processing = undefined; this.status.textContent = '原记录已修改或删除，请重新选择处理。';
        }
        if(this.editDraft&&state.entries.some(entry=>entry.id===this.editDraft!.id))return;
        if(this.editDraft){this.editDraft=undefined;this.status.textContent='编辑的记录已删除或过期。';}
        this.render(); }
    private async run(action: () => Promise<unknown>): Promise<void> {
        if (this.busy) return;
        const editor=this.detail.querySelector('textarea'),selection=editor?[editor.selectionStart,editor.selectionEnd] as const:undefined;
        let failed=false;
        this.busy = true; this.status.textContent = ''; this.render();
        try { await action(); } catch { failed=true;this.status.textContent = '操作未完成，请重试；历史条目可能已删除。'; }
        finally { this.busy = false; this.render();if(failed&&(this.editDraft||this.processing?.editing)){const input=this.detail.querySelector('textarea');input?.focus();if(input&&selection)input.setSelectionRange(...selection);} }
    }
    private button(text: string, action: () => void): HTMLButtonElement {
        const button = document.createElement('button'); button.type = 'button'; button.textContent = text;
        button.disabled = this.busy; button.onclick = () => { if (!this.busy) action(); }; return button;
    }
    private option(label: string, checked: boolean, change: (checked: boolean) => void): HTMLLabelElement {
        const wrapper = document.createElement('label'), input = document.createElement('input'); input.type = 'checkbox'; input.checked = checked; input.disabled = this.busy || Boolean(this.editDraft);
        input.onchange = () => { change(input.checked); this.render(); }; wrapper.append(input, document.createTextNode(label)); return wrapper;
    }
    private render(): void {
        const previewVersion = ++this.previewVersion;
        this.toggle.textContent = this.state.isEnabled ? '暂停记录' : this.enabledBefore ? '恢复记录' : '启用记录';
        this.toggle.disabled = this.busy || Boolean(this.editDraft); this.clear.disabled = this.busy || Boolean(this.editDraft) || !(this.state.entries.length + (this.state.images?.length ?? 0));
        this.search.disabled = this.category === 'images' || Boolean(this.editDraft);
        this.root.querySelectorAll<HTMLButtonElement>('[data-category]').forEach(button => { button.setAttribute('aria-pressed', String(button.dataset.category === this.category)); button.disabled = this.busy || Boolean(this.editDraft); });
        const query = this.search.value.toLocaleLowerCase();
        const entries = this.state.entries.filter(entry => entry.text.toLocaleLowerCase().includes(query));
        const images = this.state.images ?? [];
        const visible = this.category === 'images' ? images : entries;
        for (const id of this.selected) if (!entries.some(entry => entry.id === id)) this.selected.delete(id);
        this.count.textContent = `${this.state.isEnabled ? '正在记录' : '已暂停'} · ${visible.length} ${this.category === 'images' ? '/ 10 张' : `/ ${this.state.entries.length} 条`}`;
        if (!visible.some(entry => entry.id === this.selectedId)) this.selectedId = visible[0]?.id;
        this.list.replaceChildren(); this.detail.replaceChildren();
        for (const entry of visible) {
            const wrapper = document.createElement('div'); wrapper.className = 'history-row';
            const image = 'thumbnail' in entry;
            if (!image) wrapper.append(this.option(`选择文字 ${entries.indexOf(entry) + 1}`, this.selected.has(entry.id), checked => { this.processing = undefined; if (checked) this.selected.add(entry.id); else this.selected.delete(entry.id); }));
            const row = this.button(image ? `${entry.width} × ${entry.height}` : entry.text.slice(0, 160).replace(/\s+/g, ' '), () => { this.processing = undefined; this.selectedId = entry.id; this.render(); });
            if (image) { const thumbnail = document.createElement('img'); thumbnail.src = entry.thumbnail; thumbnail.alt = '历史图片缩略图'; row.prepend(thumbnail); }
            row.disabled ||= Boolean(this.editDraft);
            row.className = `item${entry.id === this.selectedId ? ' active' : ''}`; row.setAttribute('aria-pressed', String(entry.id === this.selectedId)); wrapper.append(row);
            if (!image) wrapper.append(clipboardTextTools(this.busy || Boolean(this.editDraft), action => this.beginProcessing(entry.id, action)));
            this.list.append(wrapper);
        }
        if(this.processing){this.renderProcessing();return;}
        if(this.editDraft){this.renderTextEditor();return;}
        if (this.category === 'text' && this.selected.size) { this.renderMerge(entries); return; }
        const selected = visible.find(entry => entry.id === this.selectedId);
        if (!selected) {
            const empty = document.createElement('p'); empty.textContent = query ? '没有匹配的历史文字。' : this.state.isEnabled ? '等待下一次复制。启用前的剪贴板不会加入历史。' : '点击启用后，才会记录新复制的文字和图片。'; this.detail.append(empty); return;
        }
        const image = 'thumbnail' in selected, heading = document.createElement('h2'); heading.textContent = image ? '历史图片' : '历史文字';
        const actions = document.createElement('div'); actions.className = 'actions';
        const use = (paste: boolean) => { void this.run(async () => { const result = await this.bridge.useClipboardHistoryEntry({id:selected.id,paste}); this.status.textContent = result.status; }); };
        actions.append(this.button(image ? '复制历史图片' : '复制历史文字', () => use(false)), this.button(image ? '粘贴历史图片' : '粘贴历史文字', () => use(true)));
        if (!image) actions.append(this.button('编辑历史文字',()=>{this.editDraft={id:selected.id,text:selected.text};this.render();this.detail.querySelector('textarea')?.focus();}),this.button('整理为常用内容', () => this.saveDraft(selected.text)));
        actions.append(this.button('删除历史', () => { void this.run(() => this.bridge.deleteClipboardHistoryEntry(selected.id)); }));
        this.detail.append(heading, actions);
        if (image) {
            const preview = document.createElement('img'); preview.className = 'history-image-preview'; preview.alt = '所选历史图片预览'; this.detail.append(preview);
            if (this.imagePreview?.id !== selected.id) this.imagePreview = {id: selected.id, pending: this.bridge.getClipboardHistoryImage(selected.id)};
            void this.imagePreview.pending.then(source => { if (this.previewVersion === previewVersion) { if(source)preview.src = source;else {this.imagePreview=undefined;preview.alt='图片暂不可用，请重新选择';} } }).catch(() => { if (this.previewVersion === previewVersion) preview.alt = '图片已删除或暂不可用'; });
        } else { const text = document.createElement('pre'); text.textContent = selected.text; this.detail.append(text); }
    }
    private beginProcessing(id: string, action: ClipboardTextAction): void {
        const entry = this.state.entries.find(entry => entry.id === id);
        if (!entry) return;
        this.processing = undefined;
        try {
            const text = processClipboardText(entry.text, action);
            this.processing = {id, action, source: entry.text, text, editing: false};
            this.selected.clear(); this.selectedId = id;
            this.status.textContent = clipboardTextNotice(entry.text, action, text) ?? '已生成预览，原记录保持不变。';
        } catch (error) { this.status.textContent = (error as Error).message; }
        this.render();
    }
    private renderProcessing(): void {
        const draft = this.processing!, heading = document.createElement('h2');
        heading.textContent = CLIPBOARD_TEXT_ACTIONS[draft.action] + ' · 预览'; this.detail.append(heading);
        let valid = true;
        try { processClipboardText(draft.text, 'original'); }
        catch (error) { valid = false; this.status.textContent = (error as Error).message; }
        const actions = document.createElement('div'); actions.className = 'actions';
        const copy = this.button('复制处理结果', () => { void this.run(async () => {
            const result = await this.bridge.useClipboardHistoryText({id: draft.id, action: draft.action, sourceText: draft.source, ...(draft.editing ? {editedText: draft.text} : {}), paste: false});
            this.status.textContent = result.status;
        }); });
        copy.disabled ||= !valid; copy.dataset.processingOutput = '';
        const edit = draft.editing ? this.button('保存到本条记录', () => { void this.run(async () => {
            await this.bridge.editClipboardHistoryEntry({id: draft.id, text: draft.text, expectedText: draft.source});
            this.processing = undefined; this.status.textContent = '已修改本条记录；系统剪贴板保持原样。';
        }); }) : this.button('编辑结果', () => { draft.editing = true; this.status.textContent = ''; this.render(); this.detail.querySelector('textarea')?.focus(); });
        if (draft.editing) { edit.disabled ||= !valid; edit.dataset.processingOutput = ''; }
        actions.append(copy, edit, this.button('取消处理', () => { this.processing = undefined; this.status.textContent = ''; this.render(); }));
        const hint = document.createElement('p'); hint.textContent = '复制不改动历史；保存仅修改本条记录，不写入剪贴板。URL 编码用于单个参数值，解码保留 +。最多 64 KiB。';
        this.detail.append(actions, hint);
        if (draft.editing) {
            const input = document.createElement('textarea'); input.className = 'history-editor'; input.value = draft.text; input.disabled = this.busy;
            input.setAttribute('aria-label', '编辑处理结果');
            input.oninput = () => {
                draft.text = input.value;
                let issue = '';
                try { processClipboardText(draft.text, 'original'); } catch (error) { issue = (error as Error).message; }
                this.detail.querySelectorAll<HTMLButtonElement>('[data-processing-output]').forEach(button => { button.disabled = this.busy || Boolean(issue); });
                this.status.textContent = issue;
            };
            this.detail.append(input);
        } else {
            const preview = document.createElement('pre'); preview.textContent = draft.text;
            preview.setAttribute('aria-label', valid ? '处理结果预览' : '原文（处理失败）'); this.detail.append(preview);
        }
    }
    private renderTextEditor(): void {
        const draft=this.editDraft!,heading=document.createElement('h2');heading.textContent='编辑历史文字';
        const input=document.createElement('textarea');input.className='history-editor';input.value=draft.text;input.disabled=this.busy;input.setAttribute('aria-label','编辑历史文字');input.oninput=()=>{draft.text=input.value;};
        const hint=document.createElement('p');hint.textContent='保存仅修改本次运行的历史，不会写入系统剪贴板；每条最多 64 KiB，合计最多 2 MiB。';
        const actions=document.createElement('div');actions.className='actions';
        actions.append(this.button('保存历史文字',()=>{void this.run(async()=>{await this.bridge.editClipboardHistoryEntry(draft);this.editDraft=undefined;this.status.textContent='已保存历史文字。';});}),this.button('取消编辑',()=>{this.editDraft=undefined;this.render();}));
        this.detail.append(heading,input,hint,actions);
    }
    private renderMerge(entries: ClipboardHistoryState['entries']): void {
        const request: ClipboardMergeRequest = {ids:entries.filter(entry => this.selected.has(entry.id)).map(entry => entry.id),trimLines:this.trimLines,collapseBlankLines:this.collapseBlankLines};
        const heading = document.createElement('h2'); heading.textContent = `合并预览 · ${request.ids.length} 条（按列表顺序）`;
        const options = document.createElement('div'); options.className = 'history-cleanup';
        options.append(this.option('去除每行首尾空白',this.trimLines,value=>{this.trimLines=value;}),this.option('合并连续空行',this.collapseBlankLines,value=>{this.collapseBlankLines=value;}));
        const preview = document.createElement('pre');
        this.detail.append(heading,options);
        try { preview.textContent = mergeHistoryText(entries.filter(entry=>this.selected.has(entry.id)).map(entry=>entry.text),request); }
        catch (error) { preview.textContent = String((error as Error).message); this.detail.append(preview); return; }
        const actions = document.createElement('div'); actions.className = 'actions';
        const use = (paste:boolean) => { void this.run(async()=>{const result=await this.bridge.useClipboardHistoryMerge({...request,paste});this.status.textContent=result.status;}); };
        actions.append(this.button('复制合并文字',()=>use(false)),this.button('粘贴合并文字',()=>use(true)),this.button('整理为常用内容',()=>{void this.run(async()=>this.saveDraft(await this.bridge.previewClipboardHistoryMerge(request)));}),this.button('取消多选',()=>{this.selected.clear();this.render();}));
        this.detail.append(actions,preview);
    }
}
