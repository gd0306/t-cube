import assert from 'node:assert/strict';
import type { Page } from 'playwright';

/** Exercises the shipped add/replace controls without launching a browser or Settings. */
export async function verifyShortcutTargetsSmoke(settings: Page): Promise<string[]> {
    await settings.getByRole('button', { name: '更多', exact: true }).click();
    for (let slot = 0; slot < 4; slot++) {
        await settings.getByRole('button', { name: '添加网站', exact: true }).nth(slot).click();
        const dialog = settings.getByRole('dialog', { name: '添加网站', exact: true });
        await dialog.getByRole('textbox', { name: '网站名称', exact: true }).fill(`Docs ${slot}`);
        await dialog.getByRole('textbox', { name: '网站地址', exact: true }).fill(`https://example.com/Docs${slot}`);
        await dialog.getByRole('button', { name: '保存', exact: true }).click();
        await dialog.waitFor({ state: 'hidden' });
        await settings.locator('.slot').nth(slot).getByText(`Docs ${slot}`, { exact: true }).waitFor();
    }
    await settings.getByRole('button', { name: '添加网站', exact: true }).first().click();
    const website = settings.getByRole('dialog', { name: '添加网站', exact: true });
    await website.getByRole('textbox', { name: '网站名称', exact: true }).fill('Unsafe');
    await website.getByRole('textbox', { name: '网站地址', exact: true }).fill('https://user:password@example.com');
    await website.getByRole('button', { name: '保存', exact: true }).click();
    await website.getByRole('status').filter({ hasText: /website|URL/i }).waitFor();
    await website.getByRole('button', { name: '取消', exact: true }).click();
    await settings.getByRole('button', { name: '系统设置', exact: true }).nth(1).click();
    const system = settings.getByRole('dialog', { name: '系统设置', exact: true });
    await system.getByRole('combobox', { name: '设置页面', exact: true }).selectOption('display');
    await system.getByRole('button', { name: '保存', exact: true }).click();
    await system.waitFor({ state: 'hidden' });
    await settings.locator('.slot').nth(1).getByText('显示', { exact: true }).waitFor();
    const snapshot = await settings.evaluate(() => window.tcube.getSnapshot());
    assert.equal(snapshot.state.configuration.groups.bottom.slots[0]?.path, 'https://example.com/Docs0');
    assert.equal(snapshot.state.configuration.groups.bottom.slots[1]?.path, 'ms-settings:display');
    for (const slot of [0, 1, 2, 3]) assert.match(snapshot.icons[snapshot.state.configuration.groups.bottom.slots[slot]!.id], /^data:image\//);
    for (const request of [
        { face: 'bottom', slot: 0, kind: 'website', name: 'Unsafe', url: 'file:///C:/Windows' },
        { face: 'bottom', slot: 0, kind: 'systemSettings', settingsId: 'ms-settings:unknown' },
    ]) {
        assert.equal(await settings.evaluate(async request => {
            try { await window.tcube.addURLTarget(request as never); return false; } catch { return true; }
        }, request), true);
    }
    await settings.getByRole('button', { name: '开发', exact: true }).click();
    return ['Website add/replace passed for all four slots; credential and unsafe-URI validation, curated settings selection and bundled URL icons passed without opening external apps.'];
}
