import test from 'node:test';
import assert from 'node:assert/strict';
import { addTarget, defaultConfiguration, moveTarget, normalizeConfiguration, removeTarget, renameGroup, resolveAppearance, THEMES } from '../src/core/configuration';
const item = (id: string, path = `C:\\Apps\\${id}.exe`) => ({ id, path, name: id, kind: 'application' as const });

test('older configurations gain new defaults without filling sparse slots', () => {
    const input = defaultConfiguration() as any;
    input.groups.front.slots[2] = item('third');
    delete input.appearance; delete input.hover; delete input.themeCycle;
    delete input.expandsFacesOnClick; delete input.autoRotatesWhenIdle;
    const restored = normalizeConfiguration(input);
    assert.equal(restored.groups.front.slots[0], null);
    assert.equal(restored.groups.front.slots[2]?.id, 'third');
    assert.equal(restored.hover.multiplier, 4);
    assert.equal(restored.appearance.surfaceStyle, 'clear');
    assert.equal(restored.appearance.material, 'glass');
    assert.equal(restored.expandsFacesOnClick, true);
    assert.equal(restored.autoRotatesWhenIdle, true);
});

test('material defaults to glass for existing appearance settings and preserves an explicit slime selection', () => {
    const original = defaultConfiguration();
    assert.equal(original.appearance.material, 'glass');
    const legacy = structuredClone(original) as any;
    delete legacy.appearance.material;
    assert.deepEqual(normalizeConfiguration(legacy).appearance, original.appearance);
    const slime = structuredClone(original);
    slime.appearance.material = 'slime';
    assert.equal(normalizeConfiguration(slime).appearance.material, 'slime');
    assert.equal(original.appearance.material, 'glass');
});

test('malformed material values fail instead of replacing a saved selection', () => {
    for (const material of [null, '', 'jelly', 1, {}, []]) {
        const config = defaultConfiguration();
        assert.throws(() => normalizeConfiguration({ ...config, appearance: { ...config.appearance, material } }), /appearance|material/i);
    }
});

test('all nine themes cycle their palette while retaining the selected physical material', () => {
    const config = defaultConfiguration();
    config.appearance.material = 'slime';
    config.appearance.glowIntensity = 0.8;
    config.themeCycle = { isEnabled: true, themes: Object.keys(THEMES) as (keyof typeof THEMES)[], intervalSeconds: 10 };
    assert.equal(config.themeCycle.themes.length, 9);
    for (const [index, theme] of config.themeCycle.themes.entries()) {
        assert.deepEqual(resolveAppearance(config, index * 10), {
            theme, appearance: { ...THEMES[theme], material: 'slime', glowIntensity: 0.8 },
        });
    }
    config.themeCycle.isEnabled = false;
    assert.equal(resolveAppearance(config, 100).appearance.material, 'slime');
});

test('target edits preserve holes, shift intervening slots, and isolate duplicate validation to each group', () => {
    let c = addTarget(defaultConfiguration(), 'front', item('a'), 2);
    c = addTarget(c, 'right', item('a'), 0);
    assert.throws(() => addTarget(c, 'front', item('b', 'c:\\apps\\a.exe'), 0), /duplicate/i);
    c = moveTarget(c, 'front', 2, 0);
    assert.deepEqual(c.groups.front.slots.map(v => v?.id ?? null), ['a', null, null, null]);
    assert.throws(() => addTarget(c, 'front', item('b'), 0), /occupied/i);
    c = removeTarget(c, 'front', 0);
    assert.deepEqual(c.groups.front.slots, [null, null, null, null]);
    assert.equal(renameGroup(c, 'front', '  Tools  ').groups.front.name, 'Tools');
    assert.equal(defaultConfiguration().groups.front.name, '常用');
});

test('malformed present values are rejected rather than silently replacing user settings', () => {
    for (const patch of [{ version: 2 }, { scale: NaN }, { scale: 1.7 }, { hover: { isEnabled: true, multiplier: 5 } },
        { appearance: { primaryHex: 'red', secondaryHex: '#000000', glowIntensity: 1 } },
        { themeCycle: { isEnabled: true, themes: ['ocean'], intervalSeconds: 10 } },
        { windowPosition: { x: Infinity, y: 0 } }, { expandsFacesOnClick: 'yes' }]) {
        assert.throws(() => normalizeConfiguration({ ...defaultConfiguration(), ...patch }));
    }
    const c = defaultConfiguration();
    assert.throws(() => normalizeConfiguration({ ...c, groups: { ...c.groups, front: { name: 'x', slots: [null] } } }));
    assert.throws(() => normalizeConfiguration({ ...c, groups: {} }));
    assert.throws(() => addTarget(c, 'front', item('bad', 'https://example.com')));
    assert.throws(() => renameGroup(c, 'front', '  '));
});

test('theme cycling uses active elapsed intervals and preserves manual glow', () => {
    const c = defaultConfiguration();
    c.appearance.glowIntensity = 0.8;
    assert.deepEqual(resolveAppearance(c, 100), { appearance: c.appearance, theme: null });
    c.themeCycle = { isEnabled: true, themes: ['prism', 'ocean'], intervalSeconds: 10 };
    assert.equal(resolveAppearance(c, 0).theme, 'prism');
    assert.equal(resolveAppearance(c, 10).theme, 'ocean');
    assert.equal(resolveAppearance(c, 20).theme, 'prism');
    assert.equal(resolveAppearance(c, 0).appearance.surfaceStyle, 'iridescent');
    assert.equal(resolveAppearance(c, 10).appearance.glowIntensity, 0.8);
});

test('replacing a requested slot is atomic and rejected duplicate ids leave the original configuration intact', () => {
    const original = addTarget(defaultConfiguration(), 'front', item('a'), 3);
    const replaced = addTarget(original, 'front', item('b'), 3, true);
    assert.equal(replaced.groups.front.slots[3]?.id, 'b');
    assert.equal(original.groups.front.slots[3]?.id, 'a');
    assert.throws(() => addTarget(original, 'front', item('a', 'D:\\Another.exe'), 0), /duplicate/i);
    assert.equal(original.groups.front.slots[0], null);
    assert.throws(() => removeTarget(original, 'front', 0), /empty/i);
    assert.throws(() => moveTarget(original, 'front', -1, 2), /invalid slot/i);
});

test('drive-root parent traversal cannot bypass duplicate detection', () => {
    const original = addTarget(defaultConfiguration(), 'front', item('first', 'C:\\Apps\\A.exe'));
    for (const path of ['C:\\..\\Apps\\A.exe', 'c:/../../Apps/./A.exe', 'C:\\Temp\\..\\..\\Apps\\A.exe']) {
        assert.throws(() => addTarget(original, 'front', item('second', path)), /duplicate/i, path);
    }
});

test('UNC parent traversal clamps at the share root and keeps shares distinct', () => {
    const original = addTarget(defaultConfiguration(), 'front', item('first', '\\\\server\\share\\Apps\\A.exe'));
    for (const path of ['\\\\server\\share\\..\\Apps\\A.exe', '\\\\SERVER\\SHARE\\..\\..\\Apps\\A.exe', '\\\\server\\share\\Temp\\..\\..\\Apps\\A.exe']) {
        assert.throws(() => addTarget(original, 'front', item('second', path)), /duplicate/i, path);
    }
    const distinct = addTarget(original, 'front', item('otherShare', '\\\\server\\other\\Apps\\A.exe'));
    assert.equal(distinct.groups.front.slots[1]?.id, 'otherShare');
});

test('verbatim namespace paths preserve literal dot components rather than applying ordinary Win32 parsing', () => {
    const original = addTarget(defaultConfiguration(), 'front', item('first', '\\\\?\\C:\\Apps\\A.exe'));
    const literal = addTarget(original, 'front', item('literal', '\\\\?\\C:\\Apps\\.\\A.exe'));
    assert.equal(literal.groups.front.slots[1]?.id, 'literal');
    assert.throws(() => addTarget(original, 'front', item('second', '\\\\?\\c:\\apps\\a.exe')), /duplicate/i);
});


test('hover delay migrates and validates finite bounded values', () => {
    const config = defaultConfiguration();
    assert.equal(config.hover.delaySeconds, 0.18);
    const legacy = structuredClone(config); delete legacy.hover.delaySeconds;
    assert.equal(normalizeConfiguration(legacy).hover.delaySeconds, 0.18);
    for (const delaySeconds of [0, 0.18, 1.5]) assert.equal(normalizeConfiguration({ ...config, hover: { ...config.hover, delaySeconds } }).hover.delaySeconds, delaySeconds);
    for (const delaySeconds of [-0.01, 1.51, NaN, Infinity, null, '0.2']) assert.throws(() => normalizeConfiguration({ ...config, hover: { ...config.hover, delaySeconds } }), /hover/i);
});
