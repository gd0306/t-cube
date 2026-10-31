import { ClipboardHistoryPanel } from './clipboard-history';
import type {} from '../shared/contracts';
import { templateVariables, renderTemplate } from '../core/snippet-template';
import type { SnippetLibrary, TextSnippet, SnippetField } from '../shared/productivity';
import { filteredSnippets, fullSnippetText, SNIPPET_LIMITS, validateSnippetText } from '../core/snippet-library';
const bridge = window.tcube;
let mode: 'library' | 'history' = 'library';
function setMode(next: typeof mode) {
    mode = next;
    document.querySelector<HTMLElement>('#library-panel')!.hidden = next !== 'library';
    document.querySelector<HTMLElement>('#history-panel')!.hidden = next !== 'history';
    document.querySelector<HTMLElement>('#snippet-actions')!.hidden = next !== 'library';
    document.querySelector('#library-mode')!.setAttribute('aria-pressed', String(next === 'library'));
    document.querySelector('#history-mode')!.setAttribute('aria-pressed', String(next === 'history'));
}
const historyPanel = new ClipboardHistoryPanel(document.querySelector<HTMLElement>('#history-panel')!, bridge, text => {
    if (newDraft(text)) setMode('library');
});
document.querySelector<HTMLButtonElement>('#library-mode')!.onclick = () => setMode('library');
document.querySelector<HTMLButtonElement>('#history-mode')!.onclick = () => setMode('history');
const list = document.querySelector<HTMLElement>('#list')!, detail = document.querySelector<HTMLElement>('#detail')!, error = document.querySelector<HTMLElement>('#error')!, status = document.querySelector<HTMLElement>('#status')!;
const search = document.querySelector<HTMLInputElement>('#search')!, favorites = document.querySelector<HTMLInputElement>('#favorites')!, group = document.querySelector<HTMLSelectElement>('#group')!;
let displayedItems: TextSnippet[] = [];
let capturePending: string | undefined;
let templateFill: { text: string; paste: boolean; values: Record<string, string> } | undefined;
let library: SnippetLibrary = { version: 1, items: [] }, selectedId: string | undefined, draft: TextSnippet | undefined, busy = false, blocked = false, reloadPending = false;
function element<K extends keyof HTMLElementTagNameMap>(tag: K, text?: string, className?: string): HTMLElementTagNameMap[K] {
    const node = document.createElement(tag); if (text !== undefined) node.textContent = text; if (className) node.className = className; return node;
}
function button(text: string, action: () => void, className?: string) { const node = element('button', text, className); node.type = 'button'; node.onclick = () => { if (!busy) action(); }; return node; }
function actions(...nodes: HTMLElement[]) { const node = element('div', undefined, 'actions'); node.append(...nodes); return node; }
function setError(reason?: unknown) { error.hidden = !reason; error.textContent = reason instanceof Error ? reason.message : reason ? String(reason) : ''; }
const priorDisabled = new WeakMap<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement | HTMLButtonElement, boolean>();
function updateBusyControls() {
    document.querySelectorAll<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement | HTMLButtonElement>('input, textarea, select, button').forEach(control => {
        if (busy) {
            if (!priorDisabled.has(control)) priorDisabled.set(control, control.disabled);
            control.disabled = true;
        } else if (priorDisabled.has(control)) {
            control.disabled = priorDisabled.get(control)!;
            priorDisabled.delete(control);
        }
    });
    detail.setAttribute('aria-busy', String(busy));
}
async function run(action: () => Promise<void>) { if (busy) return; busy = true; updateBusyControls(); setError(); try { await action(); } catch (reason) { setError(reason); } finally { busy = false; if (document.hidden && templateFill) { templateFill = undefined; render(); } updateBusyControls(); if (reloadPending) { reloadPending = false; void run(reloadLibrary); } else if (capturePending !== undefined) { const text = capturePending; capturePending = undefined; handleCapture(text); } } }
function visible() { return displayedItems; }
function update(next: SnippetLibrary) { library = next; renderGroups(); render(); }
function renderGroups() {
    const previous = group.value; group.replaceChildren(new Option('全部分组', ''));
    [...new Set(library.items.map(item => item.group).filter(Boolean))].sort((a, b) => a.localeCompare(b, 'zh-CN')).forEach(value => group.add(new Option(value, value)));
    if ([...group.options].some(option => option.value === previous)) group.value = previous;
}
function render() {
    const items = displayedItems = filteredSnippets(library, { query: search.value, group: group.value || undefined, favoritesOnly: favorites.checked });
    if (!items.some(item => item.id === selectedId)) selectedId = items[0]?.id;
    list.replaceChildren(); document.querySelector('#count')!.textContent = `${items.length} 条内容`;
    for (const item of items) {
        const row = button('', () => { if (!allowDiscard()) return; selectedId = item.id; draft = undefined; templateFill = undefined; render(); }, `item${item.id === selectedId && !draft ? ' active' : ''}`);
        row.setAttribute('aria-pressed', String(item.id === selectedId && !draft));
        row.append(element('strong', `${item.isFavorite ? '★ ' : ''}${item.title}`), element('span', `${item.group || '未分组'} · ${fullSnippetText(item).slice(0, 120).replace(/\n/g, ' ')}`)); list.append(row);
    }
    renderDetail();
    for (const id of ['#add', '#capture']) {
        const control = document.querySelector<HTMLButtonElement>(id)!;
        control.disabled = blocked;
        if (busy) priorDisabled.set(control, blocked);
    }
    // Rendering can replace controls while an operation is pending. Preserve each
    // control's own disabled state so completion does not enable unavailable actions.
    updateBusyControls();
}
function allowDiscard() { return (!draft && !templateFill) || window.confirm(templateFill ? '模板尚未使用，放弃填写？' : '当前编辑尚未保存，放弃修改？'); }
function newDraft(text = '') {
    if (blocked || !allowDiscard()) return false;
    validateSnippetText(text);
    templateFill = undefined;
    draft = { id: crypto.randomUUID(), title: text.split(/\r?\n/).find(line => line.trim())?.slice(0, 40) ?? '', group: group.value, body: text, fields: [], isFavorite: false };
    status.textContent = text ? '请检查收录文字，点击保存后才会加入内容库。' : '填写正文或字段，保存后即可快速使用。'; render(); return true;
}
function useText(text: string, paste: boolean) { void run(async () => { const result = await bridge.useSnippetText({ text, paste }); status.textContent = result.status; }); }
function prepareText(text: string, paste: boolean, isTemplate: boolean) {
    if (!isTemplate || !templateVariables(text).length) { useText(text, paste); return; }
    templateFill = { text, paste, values: Object.create(null) as Record<string, string> };
    renderDetail();
    detail.querySelector<HTMLInputElement>('input')?.focus();
}
function renderTemplateFill(fill: NonNullable<typeof templateFill>) {
    const { text, paste, values } = fill, names = templateVariables(text);
    const form = element('form', undefined, 'editor');
    form.append(element('h2', '填写模板'));
    const preview = element('pre');
    const submit = button(paste ? '粘贴' : '复制', () => {}, 'primary'); submit.type = 'submit';
    function refresh() {
        preview.textContent = renderTemplate(text, values);
        submit.disabled = names.some(name => !values[name]?.trim());
    }
    for (const name of names) {
        const label = element('label', name), input = element('input');
        input.setAttribute('aria-label', name); input.value = values[name] ?? '';
        input.oninput = () => { values[name] = input.value; refresh(); };
        label.append(input); form.append(label);
    }
    form.append(element('h3', '预览'), preview, actions(submit, button('取消', () => { templateFill = undefined; render(); })));
    form.onsubmit = event => {
        event.preventDefault();
        if (submit.disabled) return;
        void run(async () => {
            const result = renderTemplate(text, values);
            validateSnippetText(result);
            const response = await bridge.useSnippetText({ text: result, paste });
            templateFill = undefined; render(); status.textContent = response.status;
        });
    };
    refresh(); detail.append(form);
}
function renderDetail() {
    detail.replaceChildren();
    if (templateFill) { renderTemplateFill(templateFill); return; }
    if (draft) { renderEditor(draft); return; }
    const snippet = visible().find(item => item.id === selectedId);
    if (!snippet) {
        const empty = element('div', undefined, 'empty'); empty.append(element('small', 'T-CUBE / 常用内容'), element('h2', library.items.length ? '换个关键词试试' : '让常用信息随手可用'), element('p', library.items.length ? '可按标题、分组、正文和字段搜索。' : '保存地址、开票信息或常用回复。拖入文字，检查后保存。'));
        if (!library.items.length && !blocked) empty.append(button('新建第一条内容', () => newDraft(), 'primary'));
        detail.append(empty); return;
    }
    const heading = element('div', undefined, 'detail-head'), title = element('div');
    title.append(element('div', snippet.group || '未分组', 'group-name'), element('h2', snippet.title));
    const favorite = button(snippet.isFavorite ? '★ 已收藏' : '☆ 收藏', () => void run(async () => update(await bridge.saveSnippet({ ...snippet, isFavorite: !snippet.isFavorite }))));
    const edit = button('编辑', () => { draft = structuredClone(snippet); render(); }); favorite.disabled = edit.disabled = blocked;
    heading.append(title, actions(favorite, edit)); detail.append(heading, actions(button('粘贴全部', () => prepareText(fullSnippetText(snippet), true, !!snippet.isTemplate), 'primary'), button('复制全部', () => prepareText(fullSnippetText(snippet), false, !!snippet.isTemplate))));
    if (snippet.body.trim()) detail.append(element('h3', '正文'), element('pre', snippet.body));
    if (snippet.fields.length) detail.append(element('h3', '独立字段'));
    for (const field of snippet.fields) {
        const row = element('div', undefined, 'field-row'), value = element('div', undefined, 'field-copy'); value.append(element('small', field.label || '未命名字段'), element('div', field.value || '（空）', 'field-value'));
        const copy = button('复制', () => prepareText(field.value, false, !!snippet.isTemplate)), paste = button('粘贴', () => prepareText(field.value, true, !!snippet.isTemplate));
        copy.setAttribute('aria-label', `复制字段：${field.label}`); paste.setAttribute('aria-label', `粘贴字段：${field.label}`); copy.disabled = paste.disabled = !field.value;
        row.append(value, actions(copy, paste)); detail.append(row);
    }
    const footer = element('div', undefined, 'detail-footer'), movements = actions();
    for (const [offset, label] of [[-1, '↑ 前移'], [1, '↓ 后移']] as const) {
        const items = visible(), neighbor = items[items.findIndex(item => item.id === snippet.id) + offset];
        const move = button(label, () => void run(async () => update(await bridge.moveSnippet({ id: snippet.id, neighborId: neighbor.id })))); move.disabled = blocked || !neighbor || neighbor.isFavorite !== snippet.isFavorite; movements.append(move);
    }
    const remove = button('删除', () => {
        if (window.confirm(`删除「${snippet.title}」？此操作无法撤销。`)) void run(async () => { update(await bridge.deleteSnippet(snippet.id)); status.textContent = '已删除内容。'; });
    }, 'danger'); remove.disabled = blocked; footer.append(movements, remove); detail.append(footer);
}
function renderEditor(snippet: TextSnippet) {
    const form = element('form', undefined, 'editor'); form.append(element('small', library.items.some(item => item.id === snippet.id) ? '编辑内容' : '新建内容 / 保存前预览'), element('h2', '整理常用信息'));
    function input(label: string, value: string, max: number, change: (value: string) => void, multiline = false) {
        const wrap = element('label', label), control = multiline ? element('textarea') : element('input'); control.value = value; control.maxLength = max; control.oninput = () => change(control.value); wrap.append(control); form.append(wrap);
    }
    input('标题', snippet.title, SNIPPET_LIMITS.title, value => { snippet.title = value; }); input('分组（可留空）', snippet.group, SNIPPET_LIMITS.group, value => { snippet.group = value; }); input('正文', snippet.body, SNIPPET_LIMITS.text, value => { snippet.body = value; }, true);
    const templateLabel = element('label', undefined, 'favorite-label'), templateCheck = element('input'); templateCheck.type = 'checkbox'; templateCheck.checked = !!snippet.isTemplate; templateCheck.onchange = () => { snippet.isTemplate = templateCheck.checked; }; templateLabel.append(templateCheck, document.createTextNode('作为模板使用（在正文或字段中填写 {{变量名}}）')); form.append(templateLabel);
    const favorite = element('label', undefined, 'favorite-label'), check = element('input'); check.type = 'checkbox'; check.checked = snippet.isFavorite; check.onchange = () => { snippet.isFavorite = check.checked; }; favorite.append(check, document.createTextNode('加入收藏')); form.append(favorite, element('h3', '独立字段'));
    const fields = element('div');
    function renderFields() {
        fields.replaceChildren();
        for (const field of snippet.fields) {
            const row = element('div', undefined, 'field-editor'), label = element('input'), value = element('textarea'); label.value = field.label; label.placeholder = '名称，如电话'; label.maxLength = SNIPPET_LIMITS.label; label.setAttribute('aria-label', '字段名称'); value.value = field.value; value.placeholder = '字段值'; value.maxLength = SNIPPET_LIMITS.text; value.setAttribute('aria-label', '字段值'); label.oninput = () => { field.label = label.value; }; value.oninput = () => { field.value = value.value; };
            row.append(label, value, button('移除', () => { snippet.fields = snippet.fields.filter(item => item.id !== field.id); renderFields(); })); fields.append(row);
        }
        addField.disabled = snippet.fields.length >= SNIPPET_LIMITS.fields;
    }
    const addField = button('＋ 添加字段', () => { snippet.fields.push({ id: crypto.randomUUID(), label: '', value: '' } satisfies SnippetField); renderFields(); });
    renderFields(); form.append(fields, addField);
    const save = button('保存内容', () => {} , 'primary'); save.type = 'submit';
    const bottom = actions(save, button('取消', () => { if (allowDiscard()) { draft = undefined; render(); } })); bottom.classList.add('editor-actions'); form.append(bottom);
    form.onsubmit = event => {
        event.preventDefault(); void run(async () => {
            const next = await bridge.saveSnippet(snippet); draft = undefined; selectedId = snippet.id;
            search.value = ''; if (group.value !== snippet.group) group.value = ''; if (!snippet.isFavorite) favorites.checked = false;
            update(next); status.textContent = `已保存「${snippet.title.trim()}」。`;
        });
    };
    detail.append(form);
}
search.oninput = () => { if (!busy) render(); }; favorites.onchange = () => { if (!busy) render(); }; group.onchange = () => { if (!busy) render(); };
document.querySelector<HTMLButtonElement>('#add')!.onclick = () => { if (!busy) newDraft(); };
document.querySelector<HTMLButtonElement>('#capture')!.onclick = () => void run(async () => { const text = await bridge.captureClipboard(); if (!text.trim()) { status.textContent = '剪贴板中没有可保存的文字。'; return; } newDraft(text); });
document.addEventListener('dragover', event => { if (event.dataTransfer?.types.includes('text/plain')) { event.preventDefault(); document.body.classList.add('dragging'); } });
document.addEventListener('dragleave', event => { if (!event.relatedTarget) document.body.classList.remove('dragging'); });
document.addEventListener('drop', event => { event.preventDefault(); document.body.classList.remove('dragging'); if (busy) return; const text = event.dataTransfer?.getData('text/plain'); if (text?.trim()) { try { newDraft(text); } catch (reason) { setError(reason); } } });
document.addEventListener('visibilitychange', () => { if (document.hidden && !busy && templateFill) { templateFill = undefined; render(); } });
window.addEventListener('beforeunload', event => { if (draft) { event.preventDefault(); event.returnValue = ''; } });
async function reloadLibrary() { const next = await bridge.getLibrary(); draft = undefined; templateFill = undefined; blocked = false; search.value = ''; group.value = ''; favorites.checked = false; update(next); status.textContent = '内容库已从导入或备份更新。'; }
function handleCapture(text: string) {
    if (busy) { capturePending = text; return; }
    if (draft) { status.textContent = '请先保存或取消当前编辑，再收录新的文字。'; return; }
    try { if (newDraft(text)) setMode('library'); } catch (reason) { setError(reason); }
}
const unsubscribers = [bridge.onShowClipboardHistory(() => setMode('history')), bridge.onLibraryCapture(handleCapture), bridge.onLibraryChanged(() => { if (busy) reloadPending = true; else void run(reloadLibrary); })];
window.addEventListener('unload', () => { historyPanel.dispose(); unsubscribers.forEach(unsubscribe => unsubscribe()); });
void run(async () => { try { update(await bridge.getLibrary()); } catch (reason) { blocked = true; render(); throw reason; } });
