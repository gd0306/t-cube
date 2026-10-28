import type { MaintenanceBridge } from '../shared/maintenance';
function element(tag: string, text = '') { const node = document.createElement(tag); node.textContent = text; return node; }
export function renderMaintenance(content: HTMLElement) {
    const bridge = window.tcube as unknown as MaintenanceBridge;
    const root = element('section'), status = element('p'), actions = element('div'), backups = element('div'), broken = element('div'), preview = element('div');
    root.append(element('h2', '备份与修复'), element('p', '备份包含六面分组、外观与常用内容。恢复前会自动保留当前数据。Windows 仅导入有效的 Windows 启动路径；常用内容采用与 macOS 相同的格式。'), actions, status, preview, element('h3', '本地备份'), backups, element('h3', '失效启动项'), broken); content.append(root);
    const run = (action: () => Promise<void>) => { void action().catch(error => { status.textContent = error instanceof Error ? error.message : String(error); }); };
    function button(label: string, action: () => Promise<void>) { const node = document.createElement('button'); node.type = 'button'; node.textContent = label; node.onclick = () => run(async () => { node.disabled = true; try { await action(); } finally { node.disabled = false; } }); return node; }
    async function refresh() {
        const state = await bridge.getMaintenanceState();
        if (state.status) status.textContent = state.status;
        backups.replaceChildren(); broken.replaceChildren();
        if (!state.backups.length) backups.append(element('p', '尚无本地备份。'));
        for (const backup of state.backups) { const row = element('div'); row.className = 'row'; row.append(element('span', backup.name), button('预览恢复', () => showPreview(backup.id))); backups.append(row); }
        if (!state.broken.length) broken.append(element('p', '未发现失效启动项。'));
        for (const item of state.broken) { const row = element('div'); row.className = 'row'; row.append(element('span', `${item.name} · ${item.reason}`), button('重新关联', async () => { await bridge.repairLauncher({ face: item.face, slot: item.slot }); await refresh(); })); broken.append(row); }
    }
    async function showPreview(id?: string) {
        const selected = await bridge.previewImportBackup(id); preview.replaceChildren(); if (!selected) return;
        preview.append(element('h3', '确认恢复'), element('p', `${selected.name}：${selected.launcherCount} 个启动项，${selected.contentCount} 条常用内容。恢复会替换当前分组与内容。`), button('确认替换并自动备份', async () => { const result = await bridge.confirmImportBackup(selected.token); preview.replaceChildren(); status.textContent = result.status; await refresh(); }), button('取消', async () => { preview.replaceChildren(); }));
    }
    actions.append(button('导出备份…', async () => { status.textContent = (await bridge.exportBackup()).status; }), button('导入备份…', () => showPreview()), button('立即备份', async () => { status.textContent = (await bridge.createBackup()).status; await refresh(); }), button('显示备份文件夹', () => bridge.revealBackups()), button('重新扫描', refresh));
    run(refresh);
}
