import type { DesktopBridge } from '../shared/contracts';
import type { ClipboardHistoryState } from '../shared/clipboard-history';

/** Separate DOM keeps ordinary snippet and template drafts intact when changing modes. */
export class ClipboardHistoryPanel {
    private state: ClipboardHistoryState = { isEnabled: false, entries: [], totalBytes: 0 };
    private selectedId: string | undefined;
    private list = document.createElement('div');
    private detail = document.createElement('section');
    private search = document.createElement('input');
    private toggle = document.createElement('button');
    private clear = document.createElement('button');
    private count = document.createElement('span');
    private status = document.createElement('p');
    private busy = false;
    private enabledBefore = false;
    private version = 0;
    private unsubscribe: () => void;
    constructor(private readonly root: HTMLElement, private readonly bridge: DesktopBridge, private readonly saveDraft: (text: string) => void) {
        root.className = 'clipboard-history';
        const privacy = document.createElement('p');
        privacy.className = 'history-privacy';
        privacy.textContent = '默认关闭，仅记录启用后复制的文字；暂停后停止读取。历史仅保存在本次运行的内存中，退出即清空，不进入备份。最多 100 条，每条 64 KiB、合计 2 MiB。会尽力跳过应用标记的敏感内容和文件，无法识别所有密码或秘密，请按需暂停。';
        const controls = document.createElement('div'); controls.className = 'history-controls';
        this.toggle.type = this.clear.type = 'button'; this.clear.textContent = '清空历史';
        this.toggle.onclick = () => { void this.run(() => bridge.setClipboardHistoryEnabled(!this.state.isEnabled)); };
        this.clear.onclick = () => { if (window.confirm('清空本次运行的全部剪贴板历史？')) void this.run(() => bridge.clearClipboardHistory()); };
        controls.append(this.toggle, this.clear, this.count);
        const columns = document.createElement('div'); columns.className = 'history-columns';
        const aside = document.createElement('aside');
        this.search.type = 'search'; this.search.placeholder = '搜索剪贴板历史'; this.search.setAttribute('aria-label', '搜索剪贴板历史');
        this.search.oninput = () => this.render();
        this.list.className = 'history-list'; this.list.setAttribute('aria-label', '剪贴板历史列表');
        this.detail.className = 'history-detail'; this.detail.setAttribute('aria-label', '历史文字详情');
        aside.append(this.search, this.list); columns.append(aside, this.detail);
        this.status.setAttribute('role', 'status'); this.status.className = 'history-status';
        root.append(privacy, controls, columns, this.status);
        this.unsubscribe = bridge.onClipboardHistoryChanged(state => { this.version++; this.update(state); });
        const version = this.version;
        void bridge.getClipboardHistory().then(state => { if (this.version === version) this.update(state); }).catch(() => { this.status.textContent = '暂时无法读取历史状态。'; });
        this.render();
    }
    dispose(): void { this.unsubscribe(); }
    private update(state: ClipboardHistoryState): void { this.state = state; this.enabledBefore ||= state.isEnabled; this.render(); }
    private async run(action: () => Promise<unknown>): Promise<void> {
        if (this.busy) return;
        this.busy = true; this.status.textContent = ''; this.render();
        try { await action(); }
        catch { this.status.textContent = '操作未完成，请重试；历史条目可能已删除。'; }
        finally { this.busy = false; this.render(); }
    }
    private button(text: string, action: () => void): HTMLButtonElement {
        const button = document.createElement('button'); button.type = 'button'; button.textContent = text;
        button.disabled = this.busy; button.onclick = () => { if (!this.busy) action(); }; return button;
    }
    private render(): void {
        this.toggle.textContent = this.state.isEnabled ? '暂停记录' : this.enabledBefore ? '恢复记录' : '启用记录';
        this.toggle.disabled = this.busy; this.clear.disabled = this.busy || !this.state.entries.length;
        const query = this.search.value.toLocaleLowerCase();
        const entries = this.state.entries.filter(entry => entry.text.toLocaleLowerCase().includes(query));
        this.count.textContent = `${this.state.isEnabled ? '正在记录' : '已暂停'} · ${entries.length} / ${this.state.entries.length} 条`;
        if (!entries.some(entry => entry.id === this.selectedId)) this.selectedId = entries[0]?.id;
        this.list.replaceChildren(); this.detail.replaceChildren();
        for (const entry of entries) {
            const row = this.button(entry.text.slice(0, 160).replace(/\s+/g, ' '), () => { this.selectedId = entry.id; this.render(); });
            row.className = `item${entry.id === this.selectedId ? ' active' : ''}`;
            row.setAttribute('aria-pressed', String(entry.id === this.selectedId)); this.list.append(row);
        }
        const selected = entries.find(entry => entry.id === this.selectedId);
        if (!selected) {
            const empty = document.createElement('p');
            empty.textContent = query ? '没有匹配的历史文字。' : this.state.isEnabled ? '等待下一次复制。启用前的剪贴板不会加入历史。' : '点击启用后，才会记录新复制的文字。';
            this.detail.append(empty); return;
        }
        const heading = document.createElement('h2'); heading.textContent = '历史文字';
        const text = document.createElement('pre'); text.textContent = selected.text;
        const actions = document.createElement('div'); actions.className = 'actions';
        actions.append(
            this.button('复制历史文字', () => { void this.run(async () => { const result = await this.bridge.useClipboardHistoryEntry({ id: selected.id, paste: false }); this.status.textContent = result.status; }); }),
            this.button('粘贴历史文字', () => { void this.run(async () => { const result = await this.bridge.useClipboardHistoryEntry({ id: selected.id, paste: true }); this.status.textContent = result.status; }); }),
            this.button('整理为常用内容', () => this.saveDraft(selected.text)),
            this.button('删除历史', () => { void this.run(() => this.bridge.deleteClipboardHistoryEntry(selected.id)); }),
        );
        this.detail.append(heading, actions, text);
    }
}
