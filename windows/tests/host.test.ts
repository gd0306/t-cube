import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { ConfigurationStore } from '../src/core/store';
import { LauncherHost } from '../src/main/application';
import { isLocalIconPath } from '../src/main/targets';
import type { HostServices } from '../src/main/application';
import type { Rect } from '../src/shared/contracts';

const nextTurn = () => new Promise<void>(resolve => setImmediate(resolve));

test('catalog selection replaces only the requested slot and preserves the application name', async () => {
    const f = await fixture();
    try {
        const before = f.store.snapshot.groups;
        await f.host.addApplication({ face: 'front', slot: 2 }, { id: 'candidate', name: '我的应用', path: 'C:\\Picked.exe', kind: 'application' });
        assert.equal(f.store.snapshot.groups.front.slots[2]?.name, '我的应用');
        assert.equal(f.store.snapshot.groups.front.slots[0]?.id, before.front.slots[0]?.id);
        assert.deepEqual(f.store.snapshot.groups.right, before.right);
        assert.deepEqual(f.launched, []);
    } finally { await f.dispose(); }
});
async function eventually(condition: () => boolean): Promise<void> {
    const deadline = performance.now() + 3000;
    while (!condition()) {
        if (performance.now() > deadline) throw new Error('Expected asynchronous side effect did not finish');
        await nextTurn();
    }
}

async function fixture(overrides: Partial<HostServices> = {}) {
    const directory = await mkdtemp(path.join(tmpdir(), 'tcube-host-'));
    const store = new ConfigurationStore(path.join(directory, 'configuration.json'));
    await store.load();
    await store.update(config => { config.hover.isEnabled = false; config.hover.delaySeconds = 0; config.expandsFacesOnClick = false;
        config.groups.front.slots[0] = { id: 'one', name: 'Editor', path: 'C:\\Apps\\Editor.exe', kind: 'application' }; });
    let pointer = { x: 180, y: 180 };
    let input = { available: true, controlHeld: false, primaryDown: true, secondaryDown: false };
    const frames: Rect[] = [], launched: string[] = [], errors: string[] = [];
    let settings = 0, broadcasts = 0;
    const host = new LauncherHost(store, {
        platform: 'win32', cursor: () => pointer, input: () => input,
        screens: () => [{ x: 0, y: 0, width: 1920, height: 1080 }],
        setFrame: frame => frames.push(frame), setVisible: () => {}, openPath: async target => { launched.push(target); return ''; },
        showSettings: () => { settings++; }, showExpanded: () => {}, closeExpanded: () => {},
        stateChanged: () => { broadcasts++; }, iconsChanged: () => {}, error: message => errors.push(message),
        validateTarget: async target => ({ id: 'picked', name: 'Picked', path: target, kind: 'application' }),
        chooseTarget: async () => [], quit: () => {}, refreshIcons: async () => ({}), ...overrides
    });
    return { host, store, frames, launched, errors, input, get settings() { return settings; }, get broadcasts() { return broadcasts; },
        pointer: (x: number, y: number) => { pointer = { x, y }; }, dispose: async () => { await host.whenIdle(); await rm(directory, { recursive: true, force: true }); } };
}

test('native release consumes a late renderer hit once', async () => {
    const f = await fixture();
    try {
        const gestureId = f.host.beginPointer(0);
        f.input.primaryDown = false; await f.host.poll();
        assert.equal(f.host.snapshot.state.interactionActive, false);
        assert.deepEqual(f.launched, []);
        await f.host.endPointer({ gestureId, button: 0, hit: { face: 'front', slot: 0 } });
        await f.host.endPointer({ gestureId, button: 0, hit: { face: 'front', slot: 0 } });
        assert.deepEqual(f.launched, ['C:\\Apps\\Editor.exe']);
    } finally { await f.dispose(); }
});

test('outside drag suppresses late click and persists resting coordinates', async () => {
    const f = await fixture();
    try {
        const gestureId = f.host.beginPointer(0);
        f.pointer(600, 500); await f.host.poll();
        f.input.primaryDown = false; await f.host.poll();
        await f.host.endPointer({ gestureId, button: 0, hit: { face: 'front', slot: 0 } });
        await f.host.whenIdle();
        assert.deepEqual(f.launched, []);
        assert.equal(f.store.snapshot.windowPosition?.x, f.host.geometry.restingFrame.x);
        assert.equal(f.store.snapshot.windowPosition?.y, f.host.geometry.restingFrame.y);
    } finally { await f.dispose(); }
});

test('Ctrl is move-only even after Ctrl releases before the mouse', async () => {
    const f = await fixture();
    try {
        f.input.controlHeld = true; await f.host.poll();
        const gestureId = f.host.beginPointer(0);
        f.input.controlHeld = false; await f.host.poll();
        await f.host.endPointer({ gestureId, button: 0, hit: { face: 'front', slot: 0 } });
        assert.equal(f.host.snapshot.state.interactionActive, true);
        f.input.primaryDown = false; await f.host.poll();
        assert.deepEqual(f.launched, []);
    } finally { await f.dispose(); }
});

test('right click opens settings only after native button release', async () => {
    const f = await fixture();
    try {
        f.input.primaryDown = false; f.input.secondaryDown = true;
        const gestureId = f.host.beginPointer(2);
        await f.host.endPointer({ gestureId, button: 2, hit: null });
        assert.equal(f.settings, 0);
        f.input.secondaryDown = false; await f.host.poll();
        assert.equal(f.settings, 1);
    } finally { await f.dispose(); }
});

test('settings payload cannot replace targets or saved position', async () => {
    const f = await fixture();
    try {
        const candidate = f.store.snapshot;
        candidate.groups.front.slots[0] = null; candidate.windowPosition = { x: 999, y: 999 }; candidate.scale = 1.2;
        const original = f.store.snapshot;
        await f.host.applyConfiguration(candidate);
        assert.deepEqual(f.store.snapshot.groups, original.groups);
        assert.notDeepEqual(f.store.snapshot.windowPosition, candidate.windowPosition);
        assert.equal(f.store.snapshot.scale, 1.2);
    } finally { await f.dispose(); }
});

test('polling unchanged input does not flood renderer state', async () => {
    const f = await fixture();
    try { await f.host.poll(); const before = f.broadcasts; await f.host.poll(); await f.host.poll(); assert.equal(f.broadcasts, before); }
    finally { await f.dispose(); }
});

test('glass and an outside slime pointer do not broadcast global cursor movement', async () => {
    const f = await fixture();
    try {
        assert.equal(f.host.snapshot.state.pointer, null);
        f.host.poll();
        assert.equal(f.host.snapshot.state.pointer, null);
        const glassBroadcasts = f.broadcasts;
        f.pointer(190, 195); f.host.poll();
        assert.equal(f.host.snapshot.state.pointer, null);
        assert.equal(f.broadcasts, glassBroadcasts);
        const config = f.store.snapshot;
        config.appearance.material = 'slime';
        await f.host.applyConfiguration(config);
        f.pointer(-100, -100); f.host.poll();
        assert.equal(f.host.snapshot.state.pointer, null);
        const outsideBroadcasts = f.broadcasts;
        f.pointer(-200, -200); f.host.poll();
        assert.equal(f.broadcasts, outsideBroadcasts);
    } finally { await f.dispose(); }
});

test('native slime pointer uses the final clamped enlarged frame and keeps its position through Control resizing', async () => {
    const f = await fixture();
    try {
        const config = f.store.snapshot;
        config.appearance.material = 'slime';
        config.hover.isEnabled = true;
        await f.host.applyConfiguration(config);
        f.pointer(150, 170); f.host.poll();
        assert.deepEqual(f.host.geometry.displayFrame, { x: 0, y: 0, width: 656, height: 656 });
        const expected = { x: 150 / 656, y: 170 / 656 };
        assert.deepEqual(f.host.snapshot.state.pointer, expected);
        f.input.controlHeld = true; f.host.poll();
        assert.deepEqual(f.host.geometry.displayFrame, { x: 112.5, y: 127.5, width: 164, height: 164 });
        assert.deepEqual(f.host.snapshot.state.pointer, expected);
        f.input.controlHeld = false; f.host.poll();
        assert.deepEqual(f.host.snapshot.state.pointer, expected);
        f.pointer(400, 300); f.host.poll();
        assert.deepEqual(f.host.snapshot.state.pointer, { x: 400 / 656, y: 300 / 656 });
    } finally { await f.dispose(); }
});

test('material changes expose the latest sampled pointer without resetting the theme phase', async () => {
    const f = await fixture();
    try {
        const config = f.store.snapshot;
        config.themeCycle = { isEnabled: true, themes: ['ocean', 'sunset'], intervalSeconds: 10 };
        await f.host.applyConfiguration(config);
        f.pointer(161, 243); f.host.poll(13);
        assert.equal(f.host.snapshot.state.activeTheme, 'sunset');
        assert.equal(f.host.snapshot.state.pointer, null);
        const slime = f.store.snapshot;
        slime.appearance.material = 'slime';
        await f.host.applyConfiguration(slime);
        assert.deepEqual(f.host.snapshot.state.pointer, { x: 0.25, y: 0.75 });
        assert.equal(f.host.snapshot.state.activeTheme, 'sunset');
        const glass = f.store.snapshot;
        glass.appearance.material = 'glass';
        await f.host.applyConfiguration(glass);
        assert.equal(f.host.snapshot.state.pointer, null);
        assert.equal(f.host.snapshot.state.activeTheme, 'sunset');
    } finally { await f.dispose(); }
});

test('native slime contact releases during gestures, on exit, and while hidden', async () => {
    const f = await fixture();
    try {
        const config = f.store.snapshot;
        config.appearance.material = 'slime';
        await f.host.applyConfiguration(config);
        f.host.poll();
        assert.ok(f.host.snapshot.state.pointer);
        const id = f.host.beginPointer(0);
        assert.equal(f.host.snapshot.state.pointer, null);
        f.pointer(181, 181); f.host.poll();
        assert.equal(f.host.snapshot.state.pointer, null);
        await f.host.endPointer({ gestureId: id, button: 0, hit: null });
        f.input.primaryDown = false; f.host.poll();
        assert.deepEqual(f.host.snapshot.state.pointer, { x: 61 / 164, y: 61 / 164 });
        f.pointer(1000, 1000); f.host.poll();
        assert.equal(f.host.snapshot.state.pointer, null);
        f.pointer(180, 180); f.host.poll();
        assert.ok(f.host.snapshot.state.pointer);
        f.host.setVisible(false);
        f.host.poll();
        assert.equal(f.host.snapshot.state.pointer, null);
    } finally { await f.dispose(); }
});

test('launch failures reach the user and never launch unconfigured paths', async () => {
    const f = await fixture({ openPath: async () => 'Access denied' });
    try {
        await assert.rejects(f.host.launch({ face: 'front', slot: 0 }), /Access denied/);
        const gestureId = f.host.beginPointer(0);
        await f.host.endPointer({ gestureId, button: 0, hit: { face: 'front', slot: 0 } });
        f.input.primaryDown = false; f.host.poll(); await f.host.whenIdle();
        assert.match(f.errors[0], /Editor.*Access denied/);
        assert.equal(f.errors.length, 1);
        await assert.rejects(f.host.launch({ face: 'front', slot: 1 }), /empty/);
    } finally { await f.dispose(); }
});

test('a right drag rotates in place and preview fallback completes on renderer release', async () => {
    const f = await fixture();
    try {
        f.input.available = false;
        const gestureId = f.host.beginPointer(2);
        f.pointer(200, 180);
        await f.host.endPointer({ gestureId, button: 2, hit: null });
        await f.host.whenIdle();
        assert.equal(f.host.snapshot.state.interactionActive, false);
        assert.equal(f.settings, 0);
        assert.deepEqual(f.launched, []);
        assert.equal(f.store.snapshot.windowPosition, null);
        assert.deepEqual(f.host.geometry.restingFrame, { x: 120, y: 120, width: 164, height: 164 });
    } finally { await f.dispose(); }
});

test('a click hit delivered after its bounded native release lifetime is ignored', async t => {
    let time = 1000;
    t.mock.method(Date, 'now', () => time);
    const f = await fixture();
    try {
        const gestureId = f.host.beginPointer(0);
        f.input.primaryDown = false; await f.host.poll();
        time += 1501;
        await f.host.endPointer({ gestureId, button: 0, hit: { face: 'front', slot: 0 } });
        assert.deepEqual(f.launched, []);
    } finally { await f.dispose(); }
});

test('theme state publishes the displayed colors and reduced-motion preference', async () => {
    const f = await fixture();
    try {
        const config = f.store.snapshot;
        config.themeCycle = { isEnabled: true, themes: ['ocean', 'sunset'], intervalSeconds: 10 };
        await f.host.applyConfiguration(config); await f.host.poll(11, true);
        assert.equal(f.host.snapshot.state.activeTheme, 'sunset');
        assert.equal(f.host.snapshot.state.displayedAppearance.primaryHex, '#FFAA73');
        assert.equal(f.host.snapshot.state.reducedMotion, true);
        f.host.setVisible(false); assert.equal(f.host.snapshot.state.visible, false);
    } finally { await f.dispose(); }
});

test('cycle changes restart at their first theme while appearance and launcher edits retain the active phase', async () => {
    const f = await fixture();
    try {
        f.host.poll(13);
        const enabled = f.store.snapshot;
        enabled.themeCycle = { isEnabled: true, themes: ['ocean', 'sunset'], intervalSeconds: 10 };
        await f.host.applyConfiguration(enabled);
        assert.equal(f.host.snapshot.state.activeTheme, 'ocean');
        f.host.poll(23);
        assert.equal(f.host.snapshot.state.activeTheme, 'sunset');
        const appearance = f.store.snapshot;
        appearance.appearance.material = 'slime';
        appearance.appearance.primaryHex = '#123456';
        appearance.appearance.glowIntensity = 0.8;
        await f.host.applyConfiguration(appearance);
        assert.equal(f.host.snapshot.state.activeTheme, 'sunset');
        assert.equal(f.host.snapshot.state.displayedAppearance.material, 'slime');
        assert.equal(f.host.snapshot.state.displayedAppearance.glowIntensity, 0.8);
        await f.host.renameGroup({ face: 'front', name: 'Work' });
        await f.host.place('center');
        assert.equal(f.host.snapshot.state.activeTheme, 'sunset');
        f.host.poll(33);
        assert.equal(f.host.snapshot.state.activeTheme, 'ocean');
        f.host.poll(37);
        const selected = f.store.snapshot;
        selected.themeCycle.themes = ['sunset', 'ocean'];
        await f.host.applyConfiguration(selected);
        assert.equal(f.host.snapshot.state.activeTheme, 'sunset');
        f.host.poll(47);
        assert.equal(f.host.snapshot.state.activeTheme, 'ocean');
        f.host.poll(48);
        const interval = f.store.snapshot;
        interval.themeCycle.intervalSeconds = 20;
        await f.host.applyConfiguration(interval);
        assert.equal(f.host.snapshot.state.activeTheme, 'sunset');
        f.host.poll(58);
        assert.equal(f.host.snapshot.state.activeTheme, 'sunset');
        f.host.poll(68);
        assert.equal(f.host.snapshot.state.activeTheme, 'ocean');
    } finally { await f.dispose(); }
});

test('failed cycle saves preserve both the saved cycle and its elapsed phase', async t => {
    const f = await fixture();
    try {
        const enabled = f.store.snapshot;
        enabled.themeCycle = { isEnabled: true, themes: ['ocean', 'sunset'], intervalSeconds: 10 };
        await f.host.applyConfiguration(enabled);
        f.host.poll(13);
        const changed = f.store.snapshot;
        changed.themeCycle.themes = ['prism', 'forest'];
        t.mock.method(f.store, 'update', async () => { throw new Error('disk failed'); });
        await assert.rejects(f.host.applyConfiguration(changed), /disk failed/);
        assert.equal(f.host.snapshot.state.activeTheme, 'sunset');
        f.host.poll(20);
        assert.equal(f.host.snapshot.state.activeTheme, 'ocean');
    } finally { await f.dispose(); }
});

test('queued saves of the same cycle restart only when that cycle is first acknowledged', async t => {
    const f = await fixture();
    let finishFirst!: () => void;
    let finishSecond!: () => void;
    const firstGate = new Promise<void>(resolve => { finishFirst = resolve; });
    const secondGate = new Promise<void>(resolve => { finishSecond = resolve; });
    const pending: Promise<void>[] = [];
    try {
        const enabled = f.store.snapshot;
        enabled.themeCycle = { isEnabled: true, themes: ['ocean', 'sunset'], intervalSeconds: 10 };
        await f.host.applyConfiguration(enabled);
        const update = f.store.update.bind(f.store);
        let writes = 0;
        t.mock.method(f.store, 'update', async (edit: Parameters<typeof update>[0]) => {
            const ordinal = ++writes;
            const saved = await update(edit);
            await (ordinal === 1 ? firstGate : secondGate);
            return saved;
        });
        f.host.poll(13);
        const first = f.store.snapshot;
        first.themeCycle.themes = ['prism', 'ocean'];
        const second = structuredClone(first);
        second.appearance.material = 'slime';
        pending.push(f.host.applyConfiguration(first), f.host.applyConfiguration(second));
        await eventually(() => writes === 2);
        f.host.poll(37);
        assert.equal(f.host.snapshot.state.activeTheme, 'sunset');
        finishFirst();
        await pending[0];
        assert.equal(f.host.snapshot.state.activeTheme, 'prism');
        f.host.poll(48);
        assert.equal(f.host.snapshot.state.activeTheme, 'ocean');
        finishSecond();
        await pending[1];
        assert.equal(f.host.snapshot.state.activeTheme, 'ocean');
        assert.equal(f.host.snapshot.state.displayedAppearance.material, 'slime');
    } finally { finishFirst(); finishSecond(); await Promise.allSettled(pending); await f.dispose(); }
});

test('releasing an enlarged drag outside the old bounds stays enlarged under the pointer', async () => {
    const f = await fixture();
    try {
        const config = f.store.snapshot; config.hover.isEnabled = true;
        await f.host.applyConfiguration(config); await f.host.poll();
        f.host.beginPointer(0);
        f.pointer(1100, 700); await f.host.poll();
        f.input.primaryDown = false; await f.host.poll();
        assert.equal(f.host.snapshot.state.hovered, true);
        assert.equal(f.host.geometry.displayFrame.width, 656);
    } finally { await f.dispose(); }
});

test('placement reveals a hidden widget and ignores placement during an active drag', async () => {
    const visibility: boolean[] = [];
    const f = await fixture({ setVisible: visible => visibility.push(visible) });
    try {
        f.host.setVisible(false); await f.host.place('bottomRight');
        assert.equal(f.host.snapshot.state.visible, true);
        assert.equal(visibility.at(-1), true);
        const before = f.store.snapshot.windowPosition;
        f.host.beginPointer(0); await f.host.place('topLeft');
        assert.deepEqual(f.store.snapshot.windowPosition, before);
    } finally { await f.dispose(); }
});

test('the drag threshold is exactly five DIP for either button', async () => {
    for (const button of [0, 2] as const) {
        for (const distance of [4.99, 5]) {
            const f = await fixture();
            try {
                f.input.primaryDown = button === 0; f.input.secondaryDown = button === 2;
                const gestureId = f.host.beginPointer(button);
                f.pointer(180 + distance, 180); await f.host.poll();
                f.input.primaryDown = false; f.input.secondaryDown = false; await f.host.poll();
                await f.host.endPointer({ gestureId, button, hit: { face: 'front', slot: 0 } });
                assert.equal(f.launched.length, button === 0 && distance < 5 ? 1 : 0);
                assert.equal(f.settings, button === 2 && distance < 5 ? 1 : 0);
            } finally { await f.dispose(); }
        }
    }
});

test('quick placement closes an expanded face', async () => {
    let closed = 0;
    const f = await fixture({ closeExpanded: () => { closed++; } });
    try {
        const config = f.store.snapshot; config.expandsFacesOnClick = true; await f.host.applyConfiguration(config);
        const gestureId = f.host.beginPointer(0);
        f.input.primaryDown = false; await f.host.poll();
        await f.host.endPointer({ gestureId, button: 0, hit: { face: 'front', slot: 0 } });
        assert.equal(f.host.snapshot.state.expandedFace, 'front');
        await f.host.place('center');
        assert.equal(f.host.snapshot.state.expandedFace, null);
        assert.equal(closed, 1);
    } finally { await f.dispose(); }
});

test('deferred position writes do not delay native sampling or the next drag', async t => {
    const f = await fixture();
    let finish!: () => void;
    let settled = false;
    const gate = new Promise<void>(resolve => { finish = () => { settled = true; resolve(); }; });
    const config = f.store.snapshot; config.hover.isEnabled = true;
    await f.host.applyConfiguration(config); f.host.poll();
    assert.equal(f.host.snapshot.state.hovered, true);
    const update = f.store.update.bind(f.store);
    let writes = 0;
    t.mock.method(f.store, 'update', (edit: Parameters<typeof update>[0]) => { writes++; return gate.then(() => update(edit)); });
    let firstPoll: Promise<void> | void = undefined;
    try {
        const firstId = f.host.beginPointer(0);
        f.pointer(600, 500); await f.host.poll();
        f.input.primaryDown = false; firstPoll = f.host.poll();
        assert.equal(await Promise.race([Promise.resolve(firstPoll).then(() => true), nextTurn().then(() => false)]), true,
            'native sample must finish while fsync/store work remains pending');
        f.input.controlHeld = true; f.pointer(20, 20); await f.host.poll();
        assert.equal(f.host.snapshot.state.controlHeld, true);
        assert.equal(f.host.snapshot.state.hovered, false);
        f.input.primaryDown = true;
        const secondId = f.host.beginPointer(0); assert.notEqual(secondId, firstId);
        f.pointer(40, 40); await f.host.poll();
        const draggedFrame = f.frames.at(-1);
        assert.equal(settled, false);
        finish(); await f.host.whenIdle();
        assert.deepEqual(f.frames.at(-1), draggedFrame, 'an earlier write must not snap an active drag back');
        f.input.primaryDown = false; await f.host.poll();
        assert.equal(f.host.snapshot.state.interactionActive, false);
        const expected = f.host.geometry.restingFrame;
        await f.host.whenIdle();
        assert.equal(writes, 2);
        assert.deepEqual(f.store.snapshot.windowPosition, { x: expected.x, y: expected.y });
    } finally { finish(); await firstPoll; await nextTurn(); await f.dispose(); }
});

test('a deferred launch cannot collapse later native clicks or block Control sampling', async () => {
    let finish!: (error: string) => void;
    const gate = new Promise<string>(resolve => { finish = resolve; });
    const opened: string[] = [];
    const f = await fixture({ openPath: async target => { opened.push(target); return opened.length === 1 ? gate : ''; } });
    let firstPoll: Promise<void> | void = undefined;
    try {
        const config = f.store.snapshot; config.hover.isEnabled = true;
        await f.host.applyConfiguration(config); f.host.poll();
        assert.equal(f.host.snapshot.state.hovered, true);
        const firstId = f.host.beginPointer(0);
        await f.host.endPointer({ gestureId: firstId, button: 0, hit: { face: 'front', slot: 0 } });
        f.input.primaryDown = false; firstPoll = f.host.poll();
        assert.equal(await Promise.race([Promise.resolve(firstPoll).then(() => true), nextTurn().then(() => false)]), true,
            'native sample must finish while shell.openPath remains pending');
        f.input.controlHeld = true; f.pointer(-1000, -1000); await f.host.poll();
        assert.equal(f.host.snapshot.state.controlHeld, true);
        assert.equal(f.host.snapshot.state.hovered, false);
        f.pointer(180, 180); f.input.controlHeld = false; f.input.primaryDown = true; await f.host.poll();
        const secondId = f.host.beginPointer(0); assert.notEqual(secondId, firstId);
        await f.host.endPointer({ gestureId: secondId, button: 0, hit: { face: 'front', slot: 0 } });
        f.input.primaryDown = false; await f.host.poll();
        await eventually(() => opened.length === 2);
        await f.host.endPointer({ gestureId: firstId, button: 0, hit: { face: 'front', slot: 0 } });
        await f.host.endPointer({ gestureId: secondId, button: 0, hit: { face: 'front', slot: 0 } });
        assert.equal(opened.length, 2);
        await f.host.whenIdle({ includeLaunches: false });
        assert.equal(opened.length, 2, 'persistence drain must not wait for a shell launch');
        finish('Access denied');
        await eventually(() => f.errors.some(message => message.includes('Access denied')));
        assert.equal(f.errors.length, 1);
    } finally { finish(''); await firstPoll; await nextTurn(); await f.dispose(); }
});

test('icon paths exclude remote and malformed targets while allowing local preview paths', () => {
    for (const value of ['\\\\server\\share\\app.exe', 'https://example.com/app.exe', 'C:relative.exe', '\\\\?\\C:\\app.exe']) {
        assert.equal(isLocalIconPath(value, 'win32'), false, value);
        assert.equal(isLocalIconPath(value, 'darwin'), false, value);
    }
    assert.equal(isLocalIconPath('C:\\Apps\\Editor.exe', 'win32'), true);
    assert.equal(isLocalIconPath('/Applications/Editor.app', 'darwin'), true);
    assert.equal(isLocalIconPath('/Applications/Editor.app', 'win32'), false);
});

test('a failed detached position save is reported once without an unhandled rejection', async t => {
    const f = await fixture();
    const unhandled: unknown[] = [];
    const onUnhandled = (error: unknown) => { unhandled.push(error); };
    process.on('unhandledRejection', onUnhandled);
    t.mock.method(f.store, 'update', async () => { throw new Error('disk failed'); });
    try {
        f.host.beginPointer(0); f.pointer(600, 500); f.host.poll();
        f.input.primaryDown = false; f.host.poll();
        await f.host.whenIdle(); await nextTurn();
        assert.deepEqual(f.errors, ['disk failed']);
        assert.deepEqual(unhandled, []);
    } finally { process.off('unhandledRejection', onUnhandled); await f.dispose(); }
});

test('cancellation suppresses both buttons before or after native release', async () => {
    for (const button of [0, 2] as const) {
        for (const releaseFirst of [false, true]) {
            const f = await fixture();
            try {
                f.input.primaryDown = button === 0; f.input.secondaryDown = button === 2;
                const gestureId = f.host.beginPointer(button);
                if (releaseFirst) { f.input.primaryDown = false; f.input.secondaryDown = false; f.host.poll(); }
                await f.host.endPointer({ gestureId, button, hit: null, cancelled: true });
                if (!releaseFirst) { f.input.primaryDown = false; f.input.secondaryDown = false; f.host.poll(); }
                await f.host.whenIdle();
                assert.deepEqual(f.launched, []);
                assert.equal(f.settings, 0);
                assert.equal(f.host.snapshot.state.expandedFace, null);
            } finally { await f.dispose(); }
        }
    }
});

test('right click waits for late renderer release before opening settings', async () => {
    const f = await fixture();
    try {
        f.input.primaryDown = false; f.input.secondaryDown = true;
        const gestureId = f.host.beginPointer(2);
        f.input.secondaryDown = false; f.host.poll();
        assert.equal(f.settings, 0);
        await f.host.endPointer({ gestureId, button: 2, hit: null });
        assert.equal(f.settings, 1);
        await f.host.endPointer({ gestureId, button: 2, hit: null });
        assert.equal(f.settings, 1);
    } finally { await f.dispose(); }
});

test('native right release opens settings after grace when renderer end is missing', async t => {
    let time = 1000;
    t.mock.method(Date, 'now', () => time);
    const f = await fixture();
    try {
        f.input.primaryDown = false; f.input.secondaryDown = true;
        const gestureId = f.host.beginPointer(2);
        f.input.secondaryDown = false; f.host.poll();
        time += 149; f.host.poll();
        assert.equal(f.settings, 0);
        time += 1; f.host.poll();
        assert.equal(f.settings, 1);
        await f.host.endPointer({ gestureId, button: 2, hit: null });
        f.host.poll();
        assert.equal(f.settings, 1);
    } finally { await f.dispose(); }
});

test('native right fallback is suppressed by cancellation within grace', async t => {
    let time = 1000;
    t.mock.method(Date, 'now', () => time);
    const f = await fixture();
    try {
        f.input.primaryDown = false; f.input.secondaryDown = true;
        const gestureId = f.host.beginPointer(2);
        f.input.secondaryDown = false; f.host.poll();
        time += 149;
        await f.host.endPointer({ gestureId, button: 2, hit: null, cancelled: true });
        time += 100; f.host.poll();
        assert.equal(f.settings, 0);
    } finally { await f.dispose(); }
});


test('native right dragging publishes total rotation displacement without moving or saving the widget', async () => {
    const f = await fixture();
    try {
        f.input.primaryDown = false; f.input.secondaryDown = true;
        const before = f.host.geometry.displayFrame;
        const gestureId = f.host.beginPointer(2);
        f.pointer(240, 150); f.host.poll();
        assert.deepEqual(f.host.geometry.displayFrame, before);
        assert.deepEqual(f.frames.at(-1), before);
        assert.deepEqual(f.host.snapshot.state.rotationDrag, { id: gestureId, x: 60, y: -30 });
        f.pointer(180, 180); f.host.poll();
        assert.deepEqual(f.host.snapshot.state.rotationDrag, { id: gestureId, x: 0, y: 0 });
        f.input.secondaryDown = false; f.host.poll();
        await f.host.endPointer({ gestureId, button: 2, hit: { face: 'front', slot: 0 } });
        await f.host.whenIdle();
        assert.equal(f.store.snapshot.windowPosition, null);
        assert.equal(f.settings, 0);
        assert.deepEqual(f.launched, []);
    } finally { await f.dispose(); }
});

test('display changes restore normalized memory without overwriting disconnected positions or legacy data', async () => {
    let displays = [{ id: 'primary', workArea: { x: 0, y: 0, width: 1000, height: 800 } }, { id: 'left', workArea: { x: -1000, y: -200, width: 1000, height: 800 } }];
    const memory = { version: 1 as const, activeDisplayId: 'left', positions: { left: { x: 0.5, y: 0.5 } } };
    const saves: unknown[] = [];
    const f = await fixture({ screens: () => displays.map(d => d.workArea), displays: () => displays,
        displayPositions: { load: async () => structuredClone(memory), save: async next => { saves.push(structuredClone(next)); } } });
    try {
        await f.host.initializeDisplayPositions();
        assert.deepEqual(f.host.geometry.restingFrame, { x: -582, y: 118, width: 164, height: 164 });
        displays = displays.slice(0, 1); await f.host.refreshDisplays();
        assert.equal(f.host.geometry.restingFrame.x, 0);
        assert.equal(f.store.snapshot.windowPosition, null);
        assert.equal(saves.length, 0);
        displays.push({ id: 'left', workArea: { x: -1800, y: 0, width: 1800, height: 1200 } });
        await f.host.refreshDisplays();
        assert.deepEqual(f.host.geometry.restingFrame, { x: -982, y: 518, width: 164, height: 164 });
        await f.host.place('bottomRight');
        assert.equal(saves.length, 1);
        assert.equal((saves[0] as typeof memory).activeDisplayId, 'left');
    } finally { await f.dispose(); }
});

test('hidden polling cannot restart dwell and host elapsed time advances delayed hover', async () => {
    const f = await fixture();
    try {
        const config = f.store.snapshot; config.hover = { isEnabled: true, multiplier: 4, delaySeconds: 0.18 };
        await f.host.applyConfiguration(config);
        f.host.poll(0); assert.equal(f.host.geometry.hovered, false);
        f.host.poll(0.18); assert.equal(f.host.geometry.hovered, true);
        f.host.setVisible(false); f.host.poll(5); f.host.poll(6);
        assert.equal(f.host.geometry.hovered, false);
        f.host.setVisible(true); f.host.poll(6); assert.equal(f.host.geometry.hovered, false);
        f.host.poll(6.18); assert.equal(f.host.geometry.hovered, true);
    } finally { await f.dispose(); }
});

test('main-process imported configuration reloads groups, geometry and icons without replacing position with a resize', async () => {
    const { writeFile } = await import('node:fs/promises');
    const f = await fixture();
    try {
        const imported = f.store.snapshot;
        imported.groups.front.name = 'Imported'; imported.groups.front.slots[0] = null;
        imported.scale = 1.5; imported.windowPosition = { x: 700, y: 500 };
        await writeFile(f.store.filePath, JSON.stringify(imported));
        await f.host.applyImportedConfiguration(imported);
        assert.equal(f.host.snapshot.state.configuration.groups.front.name, 'Imported');
        assert.equal(f.host.snapshot.state.configuration.groups.front.slots[0], null);
        assert.deepEqual(f.host.geometry.restingFrame, { x: 700, y: 500, width: 246, height: 246 });
        f.host.poll(); await f.host.whenIdle();
        assert.deepEqual(f.store.snapshot.windowPosition, { x: 700, y: 500 });
    } finally { await f.dispose(); }
});

test('explicit placement persistence drain includes the independent display write', async () => {
    let finish!: () => void;
    const gate = new Promise<void>(resolve => { finish = resolve; });
    let saving = false;
    const f = await fixture({ displays: () => [{ id: 'primary', workArea: { x: 0, y: 0, width: 1920, height: 1080 } }],
        displayPositions: { load: async () => ({ version: 1, activeDisplayId: null, positions: {} }), save: async () => { saving = true; await gate; } } });
    try {
        await f.host.initializeDisplayPositions();
        const placing = f.host.place('center');
        await eventually(() => saving && f.store.snapshot.windowPosition?.x === 878);
        await nextTurn();
        let drained = false;
        const drain = f.host.whenIdle({ includeLaunches: false }).then(() => { drained = true; });
        await nextTurn(); assert.equal(drained, false);
        finish(); await placing; await drain; assert.equal(drained, true);
    } finally { finish(); await f.dispose(); }
});


test('imported position replaces persisted display memory so restart keeps the imported origin', async () => {
    const { writeFile } = await import('node:fs/promises');
    const { DisplayPositionStore } = await import('../src/main/display-position-store');
    const directory = await mkdtemp(path.join(tmpdir(), 'tcube-import-display-'));
    const displayStore = new DisplayPositionStore(path.join(directory, 'display-positions.json'));
    await displayStore.save({ version: 1, activeDisplayId: 'primary', positions: { primary: { x: 0.1, y: 0.1 } } });
    const services = { displays: () => [{ id: 'primary', workArea: { x: 0, y: 0, width: 1920, height: 1080 } }], displayPositions: displayStore };
    const f = await fixture(services);
    try {
        await f.host.initializeDisplayPositions();
        const imported = f.store.snapshot;
        imported.scale = 1.5; imported.windowPosition = { x: 700, y: 500 };
        await writeFile(f.store.filePath, JSON.stringify(imported));
        await f.host.applyImportedConfiguration(imported);
        f.host.poll(); await f.host.whenIdle();
        assert.deepEqual(f.store.snapshot.windowPosition, { x: 700, y: 500 });
        const restarted = await fixture({ ...services, displayPositions: new DisplayPositionStore(displayStore.filePath) });
        try {
            const config = restarted.store.snapshot; config.scale = imported.scale;
            await restarted.host.applyConfiguration(config);
            await restarted.host.initializeDisplayPositions();
            const restored = restarted.host.geometry.restingFrame;
            assert.ok(Math.abs(restored.x - 700) < 1e-9);
            assert.ok(Math.abs(restored.y - 500) < 1e-9);
            assert.equal(restored.width, 246); assert.equal(restored.height, 246);
        } finally { await restarted.dispose(); }
    } finally { await f.dispose(); await rm(directory, { recursive: true, force: true }); }
});
