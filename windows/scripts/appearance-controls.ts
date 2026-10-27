import assert from 'node:assert/strict';
import type { Page } from 'playwright';

/** Exercise the native menu interaction; selectOption bypasses popup lifetime bugs. */
export async function verifyAppearanceControls(settings: Page): Promise<void> {
    for (const [name, key, expected] of [
        ['材质', 'material', 'slime'],
        ['光效样式', 'surfaceStyle', 'iridescent'],
    ] as const) {
        const control = settings.getByRole('combobox', { name, exact: true });
        const original = await control.elementHandle();
        assert.ok(original);
        await control.click();
        await settings.keyboard.press('ArrowDown');
        await settings.keyboard.press('Enter');
        await settings.evaluate(() => new Promise<void>(resolve => {
            requestAnimationFrame(() => requestAnimationFrame(() => resolve()));
        }));
        assert.equal(await original.evaluate(element => element.isConnected), true,
            `${name}: releasing the pointer must not replace the open native select`);
        await settings.waitForFunction(async ({ key, expected }) => {
            const data = await window.tcube.getSnapshot();
            return data.state.configuration.appearance[key] === expected;
        }, { key, expected });
        assert.equal(await control.inputValue(), expected);
        await control.blur();
        await original.dispose();
    }
}
