import { CLIPBOARD_TEXT_ACTIONS, type ClipboardTextAction } from '../shared/clipboard-text-processing';

/** Per-record native menu. Choosing a tool only opens a preview. */
export function clipboardTextTools(disabled: boolean, choose: (action: ClipboardTextAction) => void): HTMLSelectElement {
    const select = document.createElement('select');
    select.className = 'clipboard-text-tools';
    select.setAttribute('aria-label', '快捷处理文字'); select.title = '快捷处理文字，先预览再复制或编辑';
    select.disabled = disabled;
    const placeholder = document.createElement('option'); placeholder.value = ''; placeholder.textContent = '处理…';
    select.append(placeholder);
    for (const [action, title] of Object.entries(CLIPBOARD_TEXT_ACTIONS)) {
        const option = document.createElement('option'); option.value = action; option.textContent = title; select.append(option);
    }
    select.onchange = () => { const action = select.value as ClipboardTextAction; select.value = ''; if (action) choose(action); };
    return select;
}
