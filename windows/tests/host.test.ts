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
    await store.update(config => { config.hover.isEnabled = false; config.expandsFacesOnClick = false;
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

test('a right drag is move-only and macOS fallback completes on renderer release', async () => {
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
        assert.notEqual(f.store.snapshot.windowPosition, null);
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
