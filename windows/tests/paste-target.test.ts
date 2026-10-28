import test from 'node:test';
import assert from 'node:assert/strict';
import { createPasteController, capturePasteTarget, pasteToTarget, type PasteBindings } from '../src/native/paste-target';
function fixture() {
    let foreground = 10n, focus = 11n, processIdentity = 'process-42-start';
    let injected = 0;
    const native: PasteBindings = {
        foreground: () => foreground,
        windowInfo: handle => handle === 10n ? { processId: 42, threadId: 7, processIdentity } : null,
        focus: () => focus,
        belongsTo: (window, child) => window === 10n && child === 11n,
        restore: () => { foreground = 10n; return true; },
        sendPaste: () => { injected++; return true; },
        ownProcessId: 99,
    };
    return { native, changeFocus: () => { focus = 12n; }, reuseProcess: () => { processIdentity = 'new-process'; }, showLibrary: () => { foreground = 20n; }, injections: () => injected };
}
test('paste restores original foreground and validates original focus before one Ctrl+V batch', async () => {
    const f = fixture(), controller = createPasteController(f.native, async () => {});
    const target = controller.capture();
    f.showLibrary();
    assert.equal(await controller.paste(target), true);
    assert.equal(f.injections(), 1);
});
test('missing, changed focus, reused process and own-window targets never inject', async () => {
    for (const scenario of ['missing', 'focus', 'reuse', 'own', 'denied'] as const) {
        const f = fixture();
        if (scenario === 'own') f.native.ownProcessId = 42;
        const controller = createPasteController(f.native, async () => {}), target = controller.capture();
        if (scenario === 'focus') f.changeFocus();
        if (scenario === 'reuse') f.reuseProcess();
        if (scenario === 'denied') f.native.restore = () => false;
        f.showLibrary();
        assert.equal(await controller.paste(scenario === 'missing' ? null : target), false);
        assert.equal(f.injections(), 0);
    }
});
test('preview platforms never load Windows bindings or paste', async () => {
    if (process.platform === 'win32') return;
    assert.equal(capturePasteTarget(), null);
    assert.equal(await pasteToTarget(null), false);
});
test('clipboard guard declines or throws without sending even to a matching target', async () => {
    for (const guard of [() => false, () => { throw new Error('Clipboard unavailable'); }]) {
        const f = fixture(), controller = createPasteController(f.native, async () => {});
        assert.equal(await controller.paste(controller.capture(), guard), false);
        assert.equal(f.injections(), 0);
    }
});
test('clipboard guard is rechecked after waiting for foreground restoration', async () => {
    const f = fixture(); let allowed = true;
    const controller = createPasteController(f.native, async () => { allowed = false; f.native.foreground = () => 10n; });
    const target = controller.capture(); f.showLibrary(); f.native.restore = () => true;
    assert.equal(await controller.paste(target, () => allowed), false);
    assert.equal(f.injections(), 0);
});
