import type { Face, URLTargetRequest } from '../shared/contracts';
import { SYSTEM_SETTINGS, websiteURL } from '../shared/shortcut-targets';

/** A modal outside #content preserves its draft during background state updates. */
export function openURLTargetPicker(face: Face, slot: number, kind: 'website' | 'systemSettings'): void {
    if (document.querySelector('.url-target-picker')) return;
    const dialog = document.createElement('dialog');
    dialog.className = 'url-target-picker';
    const title = document.createElement('h2');
    title.id = 'url-target-title';
    title.textContent = kind === 'website' ? '添加网站' : '系统设置';
    dialog.setAttribute('aria-labelledby', title.id);
    const form = document.createElement('form');
    const status = document.createElement('p');
    status.setAttribute('role', 'status');
    const name = document.createElement('input'), url = document.createElement('input'), settings = document.createElement('select');
    function field(text: string, control: HTMLInputElement | HTMLSelectElement) {
        const label = document.createElement('label');
        label.textContent = text;
        label.append(control);
        form.append(label);
    }
    if (kind === 'website') {
        name.type = 'text'; name.required = true; name.maxLength = 120;
        url.type = 'url'; url.required = true; url.maxLength = 8192; url.placeholder = 'https://example.com';
        field('网站名称', name); field('网站地址', url);
    } else {
        for (const page of SYSTEM_SETTINGS) {
            const option = document.createElement('option');
            option.value = page.id; option.textContent = page.name; settings.append(option);
        }
        field('设置页面', settings);
    }
    const footer = document.createElement('footer');
    const save = document.createElement('button'), cancel = document.createElement('button');
    save.type = 'submit'; save.textContent = '保存';
    cancel.type = 'button'; cancel.textContent = '取消'; cancel.onclick = () => dialog.close();
    footer.append(cancel, save); form.append(status, footer);
    let saving = false;
    form.onsubmit = event => {
        event.preventDefault(); if (saving) return;
        status.textContent = '';
        let request: URLTargetRequest;
        try {
            if (kind === 'website') {
                websiteURL(url.value);
                if (!name.value.trim()) throw new Error('请输入网站名称。');
                request = { face, slot, kind, name: name.value.trim(), url: url.value };
            } else request = { face, slot, kind, settingsId: settings.value };
        } catch (error) { status.textContent = error instanceof Error ? error.message : String(error); return; }
        saving = true; save.disabled = cancel.disabled = true;
        void window.tcube.addURLTarget(request).then(() => dialog.close()).catch(error => {
            status.textContent = error instanceof Error ? error.message : String(error);
        }).finally(() => { saving = false; save.disabled = cancel.disabled = false; });
    };
    dialog.addEventListener('cancel', event => { if (saving) event.preventDefault(); });
    dialog.addEventListener('close', () => dialog.remove());
    dialog.append(title, form); document.body.append(dialog); dialog.showModal();
    (kind === 'website' ? name : settings).focus();
}
