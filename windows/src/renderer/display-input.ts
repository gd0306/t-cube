import type { DisplayInputMapping } from '../shared/display-input';
import type { InputResult, InputReading } from '../native/display-input';
interface Display { identity: string; name: string; reading: InputReading | null; knownModel?: boolean }
interface Bridge { list(): Promise<{ result: InputResult; mappings: Record<string, DisplayInputMapping> }>; save(identity: string, mapping: DisplayInputMapping): Promise<void>; switch(identity: string, target: 'typeC' | 'hdmi'): Promise<InputResult>; close(): Promise<void> }
const bridge = (window as unknown as { displayInput: Bridge }).displayInput;
const get = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
const select = get<HTMLSelectElement>('display'), source = get<HTMLFieldSetElement>('source'), current = get('current'), status = get('status');
const sourceOptions = Array.from(source.querySelectorAll<HTMLInputElement>('input[type=radio]'));
const code = get('code');
const typeC = get<HTMLInputElement>('typec'), hdmi = get<HTMLInputElement>('hdmi');
const refreshButton = get<HTMLButtonElement>('refresh'), saveButton = get<HTMLButtonElement>('save');
let displays: Display[] = [], mappings: Record<string, DisplayInputMapping> = {}, busy = false, generation = 0;
function message(error: unknown): string {
    const text = String(error);
    if (/corrupt|unreadable/i.test(text)) return '输入源设置文件无法读取，请先备份并修复 display-inputs.json。';
    if (/may have been sent/i.test(text)) return '显示器状态已变化；指令可能已发送，请查看显示器。';
    if (/cancelled/i.test(text)) return '显示器操作已取消。';
    if (/Current source|not calibrated/i.test(text)) return '当前输入源无法读取或未设置，请刷新并检查代码。';
    if (/ambiguous|unavailable/i.test(text)) return '无法唯一识别此显示器，请刷新并检查连接。';
    return `操作失败：${text}`;
}
function selected() { return displays.find(display => display.identity === select.value); }
function render(preserveFields = false) {
    const display = selected(), mapping = display && mappings[display.identity], reading = display?.reading;
    select.disabled = busy || !displays.length; refreshButton.disabled = busy; saveButton.disabled = busy || !display;
    const active = reading && mapping && (reading.current === mapping.typeC ? 'Type-C' : reading.current === mapping.hdmi ? 'HDMI' : null);
    current.textContent = !display ? '未找到可唯一识别的显示器。' : active ? `当前输入源：${active}` : reading ? '当前输入源尚未匹配。' : '无法读取当前输入源。';
    code.textContent = reading ? `当前代码：${reading.current}（显示器报告的最大值：${reading.maximum}）` : '当前代码未知。';
    const value = reading && mapping && (reading.current === mapping.typeC ? 'typeC' : reading.current === mapping.hdmi ? 'hdmi' : null);
    source.disabled = busy || value === null || value === undefined;
    source.dataset.selected = value ?? 'unknown';
    source.setAttribute('aria-busy', String(busy));
    for (const option of sourceOptions) option.checked = option.value === value;
    if (!preserveFields) { typeC.value = mapping ? String(mapping.typeC) : ''; hdmi.value = mapping ? String(mapping.hdmi) : ''; }
    status.textContent = source.disabled ? '请先设置两个不同的输入代码，并激活其中一个输入源。' : '选择要切换的输入源。';
}
async function refresh() {
    const token = ++generation; busy = true; render(); status.textContent = '正在读取显示器…';
    try {
        const response = await bridge.list(); if (token !== generation) return;
        if (response.result.status !== 'listed') throw new Error('显示器返回了意外结果');
        const prior = select.value; displays = response.result.displays; mappings = response.mappings;
        for (const display of displays) if (display.knownModel && !mappings[display.identity]) mappings[display.identity] = { typeC: 7, hdmi: 5 };
        select.replaceChildren(...displays.map(display => { const option = document.createElement('option'); option.value = display.identity; option.textContent = display.name || display.identity; return option; }));
        if (displays.some(display => display.identity === prior)) select.value = prior;
    } catch (error) { if (token === generation) { busy = false; render(); status.textContent = message(error); } return; }
    if (token === generation) { busy = false; render(); }
}
select.addEventListener('change', () => render());
refreshButton.addEventListener('click', () => void refresh());
get('close').addEventListener('click', () => void bridge.close());
get('preset').addEventListener('click', () => { typeC.value = '7'; hdmi.value = '5'; });
get('save').addEventListener('click', () => void (async () => {
    const display = selected(); if (!display) return;
    if (!typeC.value || !hdmi.value || !typeC.checkValidity() || !hdmi.checkValidity() || Number(typeC.value) === Number(hdmi.value)) { status.textContent = '请输入两个不同的 0 至 65535 的整数。'; return; }
    const mapping = { typeC: Number(typeC.value), hdmi: Number(hdmi.value) };
    busy = true; render(true); status.textContent = '正在保存代码…';
    try { await bridge.save(display.identity, mapping); await refresh(); }
    catch (error) { busy = false; render(true); status.textContent = message(error); }
})());
source.addEventListener('change', event => void (async () => {
    const option = event.target;
    const display = selected(), mapping = display && mappings[display.identity];
    if (!(option instanceof HTMLInputElement) || !sourceOptions.includes(option) || !display || busy || source.disabled) return;
    const target = option.value;
    if (target !== 'typeC' && target !== 'hdmi') return;
    if (mapping && display.reading?.current === mapping[target]) { render(); return; }
    busy = true; render(); status.textContent = '正在发送切换指令…';
    try {
        const result = await bridge.switch(display.identity, target); busy = false;
        if (result.status === 'confirmed' || result.status === 'no-op' || result.status === 'not-applied') display.reading = result.reading;
        else display.reading = null;
        render();
        status.textContent = result.status === 'confirmed' ? '输入源已切换。' : result.status === 'no-op' ? '当前已使用此输入源。' : result.status === 'not-applied' ? '显示器没有切换输入源。' : '切换请求未确认，可能已执行；请查看画面。';
    } catch (error) { busy = false; display.reading = null; render(true); status.textContent = message(error); }
})());
document.addEventListener('keydown', event => { if (event.key === 'Escape') void bridge.close(); });
void refresh();
