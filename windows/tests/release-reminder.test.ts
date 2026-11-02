import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import * as reminder from '../src/main/release-reminder';
test('unsigned releases have a reminder service independent of the signed installer', () => { assert.equal(typeof reminder?.ReleaseReminderController, 'function'); });
if (reminder) {
    const { parseReminderRelease, fetchLatestRelease, ReminderStore, ReleaseReminderController } = reminder;
    const release = (tag = 'v0.19.0', extra = {}) => ({ tag_name: tag, draft: false, prerelease: false, html_url: `https://github.com/gd0306/t-cube/releases/tag/${tag}`, ...extra });
    const defaults = (): any => ({ version: 1, enabled: false, lastAttempt: null, lastNotified: null, retryUntil: null });
    function harness(saved = defaults(), response: () => Promise<unknown> = async () => release()) {
        let time = 1_000_000, calls = 0, prompts = 0, opens = 0, login = false;
        const timers = new Map<object, { delay: number; callback: () => void }>();
        const records: any[] = [];
        const store = { read: async () => structuredClone(saved), write: async (value: any) => { saved = structuredClone(value); records.push(structuredClone(value)); } };
        const controller = new ReleaseReminderController({ platform: 'win32', packaged: true, version: '0.18.1', store,
            now: () => time, schedule: (callback: () => void, delay: number) => { const timer = {}; timers.set(timer, { delay, callback }); return timer; }, cancel: (timer: object) => { timers.delete(timer); },
            fetchRelease: async (_signal: AbortSignal) => { calls++; assert.equal(records.at(-1)?.lastAttempt, time); return response(); },
            notify: async () => { prompts++; return false; }, open: async () => { opens++; }, getLogin: () => login, setLogin: (value: boolean) => { login = value; } });
        return { controller, timers, records, get saved() { return saved; }, get calls() { return calls; }, get prompts() { return prompts; }, get opens() { return opens; }, advance: (delta: number) => { time += delta; }, fire: async () => { const entry = timers.entries().next().value!; timers.delete(entry[0]); entry[1].callback(); await new Promise(resolve => setImmediate(resolve)); } };
    }
    test('release parser accepts only newer stable numeric versions on the exact release page', () => {
        assert.deepEqual(parseReminderRelease(release(), '0.18.1'), { version: '0.19.0', tag: 'v0.19.0', url: 'https://github.com/gd0306/t-cube/releases/tag/v0.19.0' });
        for (const tag of ['0.18.1', 'v0.17.9', 'v01.19.0', 'v0.19.0-beta', 'v9007199254740992.0.0', 'v0.19', '../evil', 'v0.19.0\n']) assert.equal(parseReminderRelease(release(tag), '0.18.1'), null);
        for (const extra of [{ draft: true }, { prerelease: true }, { html_url: 'https://evil.test' }, { html_url: 'https://github.com/gd0306/t-cube/releases/tag/v0.19.0?x=1' }, { draft: undefined }]) assert.equal(parseReminderRelease(release('v0.19.0', extra), '0.18.1'), null);
        assert.equal(parseReminderRelease(release(), 'broken'), null);
    });
    test('default-off starts no network or timer and keeps unsigned installation unavailable', async () => {
        const h = harness(); await h.controller.start(); await h.controller.start(); const state = await h.controller.getLifecycleState();
        assert.equal(h.calls, 0); assert.equal(h.timers.size, 0); assert.equal(state.automaticUpdates, false); assert.equal(state.updateMode, 'reminder'); assert.equal(state.checksSupported, true); assert.equal(state.updatesEnabled, false); assert.equal(state.updateReady, false);
        await h.controller.setLoginEnabled(true); assert.equal((await h.controller.getLifecycleState()).loginEnabled, true); await h.controller.installUpdate(); assert.equal(h.calls, 0);
    });
    test('manual checks work without opt-in and apply persisted 60 second cooldown', async () => {
        const h = harness(); await h.controller.start(); assert.equal((await h.controller.checkForUpdates()).latestVersion, '0.19.0'); assert.equal(h.calls, 1); assert.equal(h.prompts, 0); assert.equal(h.timers.size, 0);
        await h.controller.checkForUpdates(); assert.equal(h.calls, 1); h.advance(60_000); await h.controller.checkForUpdates(); assert.equal(h.calls, 2);
    });
    test('opt-in checks immediately and prompts each version once across restarts', async () => {
        const h = harness(); await h.controller.setAutomaticUpdates(true); assert.equal(h.calls, 1); assert.equal(h.prompts, 1); assert.equal(h.saved.lastNotified, '0.19.0'); assert.equal(h.timers.size, 1); assert.equal([...h.timers.values()][0].delay, 21_600_000);
        h.advance(21_600_000); await h.fire(); assert.equal(h.calls, 2); assert.equal(h.prompts, 1);
        const restarted = harness(h.saved); restarted.advance(21_600_000); await restarted.controller.start(); assert.equal(restarted.calls, 0); assert.equal(restarted.timers.size, 1); await h.controller.setAutomaticUpdates(false); assert.equal(h.timers.size, 0);
    });
    test('recent startup schedules remaining interval and stale startup checks immediately', async () => {
        const h = harness({ ...defaults(), enabled: true, lastAttempt: 500_000 }); await h.controller.start(); assert.equal(h.calls, 0); assert.equal([...h.timers.values()][0].delay, 21_100_000); assert.match((await h.controller.getLifecycleState()).status, /已开启/);
        const stale = harness({ ...defaults(), enabled: true, lastAttempt: 0 }); stale.advance(21_600_000); await stale.controller.start(); assert.equal(stale.calls, 1);
    });
    test('disable invalidates in-flight automatic check and suppresses late prompts', async () => {
        let complete!: (value: unknown) => void; const h = harness(defaults(), () => new Promise(resolve => { complete = resolve; }));
        const enabling = h.controller.setAutomaticUpdates(true); await new Promise(resolve => setImmediate(resolve)); await h.controller.setAutomaticUpdates(false); complete(release()); await enabling;
        assert.equal(h.prompts, 0); assert.equal(h.saved.lastNotified, null); assert.equal(h.timers.size, 0);
    });
    test('concurrent requests share one flight', async () => {
        let complete!: (value: unknown) => void; const h = harness(defaults(), () => new Promise(resolve => { complete = resolve; }));
        const first = h.controller.checkForUpdates(); await new Promise(resolve => setImmediate(resolve)); const second = h.controller.checkForUpdates(); complete(release()); await Promise.all([first, second]); assert.equal(h.calls, 1);
    });
    test('store defaults safely, serializes writes and preserves corrupt JSON', async () => {
        const dir = await mkdtemp(join(tmpdir(), 'tcube-reminder-')); const path = join(dir, 'release-reminder.json');
        try { const store = new ReminderStore(path); assert.deepEqual(await store.read(), defaults()); await Promise.all([store.write({ ...defaults(), enabled: true }), store.write({ ...defaults(), lastAttempt: 123 })]); assert.equal(JSON.parse(await readFile(path, 'utf8')).lastAttempt, 123);
            await writeFile(path, '{broken'); const corrupt = new ReminderStore(path); await assert.rejects(corrupt.read()); await assert.rejects(corrupt.write(defaults())); assert.equal(await readFile(path, 'utf8'), '{broken');
        } finally { await rm(dir, { recursive: true, force: true }); }
    });
    test('transport pins anonymous HTTPS request and rejects redirects and oversized streamed bodies', async () => {
        let request: RequestInit | undefined;
        const result = await fetchLatestRelease(new AbortController().signal, async (url: string, init: RequestInit) => { assert.equal(url, 'https://api.github.com/repos/gd0306/t-cube/releases/latest'); request = init; return new Response(JSON.stringify(release())); });
        assert.equal((result as any).tag_name, 'v0.19.0'); assert.equal(request?.redirect, 'error'); assert.equal(request?.credentials, 'omit'); assert.deepEqual(request?.headers, { Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'T-Cube-release-reminder' });
        await assert.rejects(fetchLatestRelease(new AbortController().signal, async () => new Response('', { status: 302, headers: { Location: 'https://evil.test' } })));
        await assert.rejects(fetchLatestRelease(new AbortController().signal, async () => new Response(new ReadableStream({ start(controller) { controller.enqueue(new Uint8Array(512 * 1024)); controller.enqueue(new Uint8Array(1)); controller.close(); } }))));
    });
    test('rate limits persist bounded retry deadline and suppress requests', async () => {
        const h = harness(defaults(), async () => fetchLatestRelease(new AbortController().signal, async () => new Response('secret error body', { status: 429, headers: { 'Retry-After': '999999999' } }), () => 1_000_000));
        const state = await h.controller.checkForUpdates(); assert.doesNotMatch(state.status, /secret/); assert.equal(h.saved.retryUntil, 87_400_000); h.advance(60_000); await h.controller.checkForUpdates(); assert.equal(h.calls, 1);
    });
    test('transport honors reset time and refuses false content-length claims', async () => {
        await assert.rejects(fetchLatestRelease(new AbortController().signal, async () => new Response('x'.repeat(512 * 1024 + 1), { headers: { 'Content-Length': '1' } })));
        await assert.rejects(fetchLatestRelease(new AbortController().signal, async () => new Response('', { status: 403, headers: { 'X-RateLimit-Reset': '1300' } }), () => 1_000_000), (error: any) => error.retryUntil === 1_300_000);
    });
}

test('metadata request aborts after 15 seconds rather than waiting indefinitely', async t => {
    t.mock.timers.enable({ apis: ['setTimeout'] });
    let settled = false;
    const operation = reminder.fetchLatestRelease(new AbortController().signal, async (_url, init) => new Promise((_resolve, reject) => {
        init.signal!.addEventListener('abort', () => { settled = true; reject(new Error('aborted')); });
    }));
    const rejection = assert.rejects(operation);
    t.mock.timers.tick(14_999); assert.equal(settled, false);
    t.mock.timers.tick(1); await rejection; assert.equal(settled, true);
});

test('failed notification is retried later and only a successful dialog records the version', async () => {
    let now = 100_000, notices = 0, saved: reminder.ReminderPreferences = { version: 1, enabled: true, lastAttempt: null, lastNotified: null, retryUntil: null };
    const opened: string[] = [];
    const controller = new reminder.ReleaseReminderController({ platform: 'win32', packaged: true, version: '0.18.1', now: () => now,
        store: { read: async () => saved, write: async value => { saved = value; } }, getLogin: () => false, setLogin: () => {},
        schedule: () => ({}), cancel: () => {}, fetchRelease: async () => ({ tag_name: 'v0.19.0', html_url: 'https://github.com/gd0306/t-cube/releases/tag/v0.19.0', draft: false, prerelease: false, assets: [{ browser_download_url: 'https://evil.test/installer.exe' }] }),
        notify: async () => { notices++; if (notices === 1) throw new Error('dialog failure'); return true; }, open: async url => { opened.push(url); } });
    await controller.start(); assert.equal(saved.lastNotified, null); assert.equal(opened.length, 0);
    now += 21_600_000; await controller.start(); assert.equal(saved.lastNotified, '0.19.0'); assert.deepEqual(opened, ['https://github.com/gd0306/t-cube/releases/tag/v0.19.0']);
    now += 21_600_000; await controller.start(); assert.equal(notices, 2); controller.dispose();
});

test('suspend aborts the fetch, blocks late dialog and resumes with the remaining interval', async () => {
    let finish!: (value: unknown) => void, signal: AbortSignal | undefined, prompts = 0, writes = 0;
    const schedules: number[] = [];
    const controller = new reminder.ReleaseReminderController({ platform: 'win32', packaged: true, version: '0.18.1', now: () => 100_000,
        store: { read: async () => ({ version: 1, enabled: true, lastAttempt: null, lastNotified: null, retryUntil: null }), write: async () => { writes++; } }, getLogin: () => false, setLogin: () => {},
        schedule: (_callback, delay) => { schedules.push(delay); return {}; }, cancel: () => {}, fetchRelease: async value => { signal = value; return new Promise(resolve => { finish = resolve; }); }, notify: async () => { prompts++; return false; }, open: async () => {} });
    const starting = controller.start(); await new Promise(resolve => setImmediate(resolve)); controller.pause(); assert.equal(signal!.aborted, true);
    finish({ tag_name: 'v0.19.0', html_url: 'https://github.com/gd0306/t-cube/releases/tag/v0.19.0', draft: false, prerelease: false }); await starting;
    assert.equal(prompts, 0); assert.equal(schedules.length, 0); await controller.resume(); assert.deepEqual(schedules, [21_600_000]); assert.equal(writes, 1); controller.dispose();
});

test('unreadable preferences block checks and writes; malformed runtime preferences never touch the OS', async () => {
    let calls = 0;
    const controller = new reminder.ReleaseReminderController({ platform: 'win32', packaged: true, version: '0.18.1', store: { read: async () => { throw new Error('corrupt'); }, write: async () => { calls++; } }, getLogin: () => false, setLogin: () => { calls++; }, fetchRelease: async () => { calls++; }, notify: async () => true, open: async () => { calls++; } });
    await controller.start(); await controller.checkForUpdates(); assert.equal((await controller.getLifecycleState()).checksSupported, false);
    await assert.rejects(controller.setAutomaticUpdates(true));
    for (const value of [null, 'true', 1, {}, undefined]) { await assert.rejects(controller.setLoginEnabled(value as boolean)); await assert.rejects(controller.setAutomaticUpdates(value as boolean)); }
    assert.equal(calls, 0); controller.dispose();
});

test('automatic reminders retain highest notified version when latest release moves backward', async () => {
    let now = 100_000, tag = 'v0.19.0', notices = 0, saved: reminder.ReminderPreferences = { version: 1, enabled: true, lastAttempt: null, lastNotified: null, retryUntil: null };
    const controller = new reminder.ReleaseReminderController({ platform: 'win32', packaged: true, version: '0.18.1', now: () => now,
        store: { read: async () => saved, write: async value => { saved = value; } }, getLogin: () => false, setLogin: () => {}, schedule: () => ({}), cancel: () => {},
        fetchRelease: async () => ({ tag_name: tag, html_url: `https://github.com/gd0306/t-cube/releases/tag/${tag}`, draft: false, prerelease: false }), notify: async () => { notices++; return false; }, open: async () => {} });
    await controller.start(); tag = 'v0.20.0'; now += 21_600_000; await controller.start();
    tag = 'v0.19.0'; now += 21_600_000; await controller.start();
    assert.equal(notices, 2); assert.equal(saved.lastNotified, '0.20.0'); assert.equal((await controller.getLifecycleState()).latestVersion, '0.19.0'); controller.dispose();
});

test('preference write failure disables future background requests', async () => {
    let now = 100_000, writes = 0, requests = 0;
    const controller = new reminder.ReleaseReminderController({ platform: 'win32', packaged: true, version: '0.18.1', now: () => now,
        store: { read: async () => ({ version: 1, enabled: true, lastAttempt: null, lastNotified: null, retryUntil: null }), write: async () => { writes++; throw new Error('disk full'); } }, getLogin: () => false, setLogin: () => {}, schedule: () => ({}), cancel: () => {}, fetchRelease: async () => { requests++; }, notify: async () => true, open: async () => {} });
    await controller.start(); now += 21_600_000; await controller.start();
    assert.equal(requests, 0); assert.equal(writes, 1); assert.equal((await controller.getLifecycleState()).checksSupported, false); controller.dispose();
});

test('malformed metadata never masquerades as a successful no-update check', async () => {
    for (const metadata of [null, {}, { tag_name: 'v0.20.0', draft: true, prerelease: false, html_url: 'https://github.com/gd0306/t-cube/releases/tag/v0.20.0' }, { tag_name: 'v0.20.0', draft: false, prerelease: false, html_url: 'https://evil.test' }, { tag_name: 'v01.20.0', draft: false, prerelease: false, html_url: 'https://github.com/gd0306/t-cube/releases/tag/v01.20.0' }]) {
        const controller = new reminder.ReleaseReminderController({ platform: 'win32', packaged: true, version: '0.19.0', store: { read: async () => ({ version: 1, enabled: false, lastAttempt: null, lastNotified: null, retryUntil: null }), write: async () => {} }, getLogin: () => false, setLogin: () => {}, fetchRelease: async () => metadata, notify: async () => { throw new Error('must not notify'); }, open: async () => { throw new Error('must not open'); } });
        const state = await controller.checkForUpdates(); assert.match(state.status, /检查新版本失败/); assert.equal(state.latestVersion, undefined); controller.dispose();
    }
});

test('rate limits without valid headers default to one hour while valid short headers retain one minute floor', async () => {
    for (const status of [403, 429]) {
        for (const headers of [{}, { 'Retry-After': 'invalid', 'X-RateLimit-Reset': 'invalid' }] as HeadersInit[])
            await assert.rejects(reminder.fetchLatestRelease(new AbortController().signal, async () => new Response('', { status, headers }), () => 1_000_000), (error: any) => error.retryUntil === 4_600_000);
    }
    await assert.rejects(reminder.fetchLatestRelease(new AbortController().signal, async () => new Response('', { status: 429, headers: { 'Retry-After': '0' } }), () => 1_000_000), (error: any) => error.retryUntil === 1_060_000);
});

test('future lastAttempt after a clock rollback allows one check then restores the normal cooldown', async () => {
    for (const enabled of [false, true]) {
        let requests = 0, saved: reminder.ReminderPreferences = { version: 1, enabled, lastAttempt: 9_999_999_999, lastNotified: null, retryUntil: null };
        const controller = new reminder.ReleaseReminderController({ platform: 'win32', packaged: true, version: '0.19.0', now: () => 100_000,
            store: { read: async () => saved, write: async value => { saved = value; } }, getLogin: () => false, setLogin: () => {}, schedule: () => ({}), cancel: () => {},
            fetchRelease: async () => { requests++; return { tag_name: 'v0.19.0', html_url: 'https://github.com/gd0306/t-cube/releases/tag/v0.19.0', draft: false, prerelease: false }; }, notify: async () => false, open: async () => {} });
        if (enabled) await controller.start(); else await controller.checkForUpdates();
        assert.equal(requests, 1); assert.equal(saved.lastAttempt, 100_000); assert.match((await controller.getLifecycleState()).status, /当前未发现更新的稳定版本/); await controller.checkForUpdates(); assert.equal(requests, 1); controller.dispose();
    }
});

test('oversized reminder preferences are rejected without replacing the original file', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'tcube-reminder-limit-')); const path = join(dir, 'release-reminder.json');
    try {
        const original = JSON.stringify({ version: 1, enabled: true, lastAttempt: null, lastNotified: null, retryUntil: null }) + ' '.repeat(16 * 1024);
        await writeFile(path, original); const store = new reminder.ReminderStore(path);
        await assert.rejects(store.read()); await assert.rejects(store.write({ version: 1, enabled: false, lastAttempt: null, lastNotified: null, retryUntil: null })); assert.equal(await readFile(path, 'utf8'), original);
    } finally { await rm(dir, { recursive: true, force: true }); }
});

test('pending disable blocks concurrent startup and resume before the preference write commits', async () => {
    for (const action of ['start', 'resume'] as const) {
        let finishWrite!: () => void, requests = 0, writes = 0;
        let saved: reminder.ReminderPreferences = { version: 1, enabled: true, lastAttempt: null, lastNotified: null, retryUntil: null };
        const controller = new reminder.ReleaseReminderController({ platform: 'win32', packaged: true, version: '0.19.0', now: () => 100_000,
            store: { read: async () => saved, write: async value => { writes++; if (writes === 1) await new Promise<void>(resolve => { finishWrite = resolve; }); saved = value; } }, getLogin: () => false, setLogin: () => {}, schedule: () => ({}), cancel: () => {},
            fetchRelease: async () => { requests++; return { tag_name: 'v0.20.0', html_url: 'https://github.com/gd0306/t-cube/releases/tag/v0.20.0', draft: false, prerelease: false }; }, notify: async () => { throw new Error('must not notify'); }, open: async () => {} });
        await controller.getLifecycleState(); const disabling = controller.setAutomaticUpdates(false); await new Promise(resolve => setImmediate(resolve));
        const starting = controller[action](); await new Promise(resolve => setImmediate(resolve)); finishWrite(); await Promise.all([disabling, starting]);
        assert.equal(requests, 0); assert.equal((await controller.getLifecycleState()).automaticUpdates, false); controller.dispose();
    }
});

test('far-future retry deadline uses a bounded timer instead of overflowing Node into a busy loop', async () => {
    let requests = 0, now = 100_000; const timers: { callback: () => void; delay: number }[] = [];
    const controller = new reminder.ReleaseReminderController({ platform: 'win32', packaged: true, version: '0.19.0', now: () => now,
        store: { read: async () => ({ version: 1, enabled: true, lastAttempt: null, lastNotified: null, retryUntil: 9_999_999_999_999 }), write: async () => {} }, getLogin: () => false, setLogin: () => {},
        schedule: (callback, delay) => { timers.push({ callback, delay }); return {}; }, cancel: () => {}, fetchRelease: async () => { requests++; }, notify: async () => false, open: async () => {} });
    await controller.start(); assert.equal(timers[0].delay, 86_400_000); assert.equal(requests, 0);
    now += 86_400_000; timers[0].callback(); await new Promise(resolve => setImmediate(resolve));
    assert.equal(timers[1].delay, 86_400_000); assert.equal(requests, 0); controller.dispose();
});
