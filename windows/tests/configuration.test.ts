import test from 'node:test';
import assert from 'node:assert/strict';
import { addTarget, defaultConfiguration, moveTarget, normalizeConfiguration, removeTarget, renameGroup, resolveAppearance } from '../src/core/configuration';
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
    assert.equal(restored.expandsFacesOnClick, true);
    assert.equal(restored.autoRotatesWhenIdle, true);
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
