import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fitWebsiteTitle, padTransparentRGB, wheelDelta } from '../src/renderer/util';

test('website captions normalize whitespace and truncate measured graphemes with an ellipsis', () => {
    const fit = fitWebsiteTitle;
    const measure = (text: string) => Array.from(new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(text)).length * 10;
    assert.equal(fit('  文档\n  入口  ', 100, measure), '文档 入口');
    assert.equal(fit('文档入口很长', 40, measure), '文档入…');
    assert.equal(fit('👨‍👩‍👧‍👦ABC', 30, measure), '👨‍👩‍👧‍👦A…');
    assert.equal(fit('A'.repeat(10000), 100000, measure), 'A'.repeat(119) + '…');
    assert.equal(fit('文档', 5, measure), '');
    assert.equal(fit('文档', NaN, measure), '');
});

test('transparent padding extends color without changing coverage', () => {
    const data = new Uint8ClampedArray(5 * 4);
    data.set([100, 150, 200, 255], 8);
    padTransparentRGB(data, 5, 1, 1);
    assert.deepEqual(
        Array.from(data),
        [0, 0, 0, 0, 100, 150, 200, 0, 100, 150, 200, 255, 100, 150, 200, 0, 0, 0, 0, 0],
    );
});
test('wheel maps Chrome vertical and shift wheel to native axes', () => {
    assert.deepEqual(wheelDelta(0, 3, false, 0), { dx: 0, dy: -3, precise: true });
    assert.deepEqual(wheelDelta(0, 1, true, 1), { dx: -1, dy: 0, precise: false });
});

import {
    PreferenceQueue,
    NameDraft,
    gestureHit,
    shouldDeferSettingsRender,
} from '../src/renderer/state';
import { defaultConfiguration } from '../src/core/configuration';

test('cancelled or lost pointer capture never sends a picked hit', () => {
    const hit = { face: 'front' as const, slot: 1 };
    assert.deepEqual(
        gestureHit('pointerup', () => hit),
        hit,
    );
    assert.equal(
        gestureHit('pointercancel', () => {
            throw new Error('must not pick');
        }),
        null,
    );
    assert.equal(
        gestureHit('lostpointercapture', () => {
            throw new Error('must not pick');
        }),
        null,
    );
});

test('rapid preference edits are serialized and rebased on acknowledged configuration', async () => {
    let stored = defaultConfiguration();
    let release!: () => void;
    const first = new Promise<void>((resolve) => {
        release = resolve;
    });
    let calls = 0;
    const queue = new PreferenceQueue(
        stored,
        async (config) => {
            calls++;
            if (calls === 1) await first;
            stored = structuredClone(config);
        },
        async () => structuredClone(stored),
    );
    const a = queue.edit((c) => {
        c.hover.multiplier = 2;
    });
    const b = queue.edit((c) => {
        c.autoRotatesWhenIdle = false;
    });
    assert.equal(queue.draft.hover.multiplier, 2);
    assert.equal(queue.draft.autoRotatesWhenIdle, false);
    release();
    await Promise.all([a, b]);
    assert.equal(stored.hover.multiplier, 2);
    assert.equal(stored.autoRotatesWhenIdle, false);
});

test('name draft survives unrelated refresh until its rename is confirmed', () => {
    const draft = new NameDraft();
    draft.change('front', '正在输入');
    assert.equal(draft.value('front', '旧名称'), '正在输入');
    draft.commit('front', '正在输入');
    draft.observe('front', '旧名称');
    assert.equal(draft.value('front', '旧名称'), '正在输入');
    draft.observe('front', '正在输入');
    assert.equal(draft.value('front', '新名称'), '新名称');
});

test('icon refresh defers settings redraw while group name is focused', () => {
    assert.equal(shouldDeferSettingsRender('groups', 'group-name'), true);
    assert.equal(shouldDeferSettingsRender('groups', null), false);
    assert.equal(shouldDeferSettingsRender('appearance', 'group-name'), false);
});

test('settings refresh preserves focused native select menus on every page', () => {
    assert.equal(shouldDeferSettingsRender('appearance', 'material', 'SELECT'), true);
    assert.equal(shouldDeferSettingsRender('appearance', 'style', 'SELECT'), true);
    assert.equal(shouldDeferSettingsRender('behavior', null, 'SELECT'), true);
    assert.equal(shouldDeferSettingsRender('appearance', null, 'BUTTON'), false);
});

test('website globe uses a monochrome bounded canvas path rather than a text prefix', async () => {
    const { drawWebsiteGlobe } = await import('../src/renderer/util');
    const ellipses: number[][] = [];
    let strokes = 0, text = 0;
    const context = {
        save() {}, restore() {}, beginPath() {},
        ellipse(...values: number[]) { ellipses.push(values); },
        moveTo() {}, lineTo() {}, stroke() { strokes++; },
        fillText() { text++; }, strokeStyle: '', lineWidth: 0,
    };
    drawWebsiteGlobe(context as unknown as CanvasRenderingContext2D, 10, 20, 16);
    assert.equal(context.strokeStyle, 'white');
    assert.equal(strokes, 1); assert.equal(text, 0);
    assert.equal(ellipses.length, 2);
    for (const [x, y, rx, ry] of ellipses) {
        assert.equal(x, 18); assert.equal(y, 28);
        assert.ok(x - rx >= 10 && x + rx <= 26 && y - ry >= 20 && y + ry <= 36);
    }
});
