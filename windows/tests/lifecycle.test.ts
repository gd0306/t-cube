import test from 'node:test';
import assert from 'node:assert/strict';
import { updatePolicy, LifecycleController } from '../src/main/lifecycle';
test('updates require packaged Windows app and embedded publisher identity', () => {
    assert.equal(updatePolicy('win32', true, ['Example Inc']).enabled, true);
    for (const [platform, packaged, publishers] of [['darwin', true, ['A']], ['win32', false, ['A']], ['win32', true, []]] as const)
        assert.equal(updatePolicy(platform, packaged, [...publishers]).enabled, false);
});
test('login only changes after explicit request and unsigned update requests never reach updater', async () => {
    let login = false, calls = 0;
    const controller = new LifecycleController({ platform: 'win32', packaged: true, version: '0.16.0', publishers: [],
        getLogin: () => login, setLogin: value => { login = value; calls++; },
        readAutomaticUpdates: async () => false, writeAutomaticUpdates: async () => {},
        updater: () => { throw new Error('must not load unsigned updater'); },
        confirmDownload: async () => true, confirmInstall: async () => true, openReleasePage: async () => {} });
    assert.equal((await controller.getLifecycleState()).loginEnabled, false); assert.equal(calls, 0);
    await controller.setLoginEnabled(true); assert.equal(login, true); assert.equal(calls, 1);
    await controller.checkForUpdates(); assert.equal((await controller.getLifecycleState()).updatesEnabled, false);
    await assert.rejects(controller.setAutomaticUpdates(true));
});
test('signed update download and installation each require explicit confirmation', async () => {
    let downloads = 0, installs = 0, allowDownload = false, allowInstall = false;
    const updater = { autoDownload: true, autoInstallOnAppQuit: true, on: () => {}, checkForUpdates: async () => ({ isUpdateAvailable: true, updateInfo: { version: '0.17.0' } }), downloadUpdate: async () => { downloads++; }, quitAndInstall: () => { installs++; } };
    const controller = new LifecycleController({ platform: 'win32', packaged: true, version: '0.16.0', publishers: ['Trusted Publisher'],
        getLogin: () => false, setLogin: () => {}, readAutomaticUpdates: async () => false, writeAutomaticUpdates: async () => {},
        updater: () => updater, confirmDownload: async () => allowDownload, confirmInstall: async () => allowInstall, openReleasePage: async () => {} });
    await controller.checkForUpdates(); assert.equal(downloads, 0); assert.equal(updater.autoDownload, false); assert.equal(updater.autoInstallOnAppQuit, false);
    allowDownload = true; assert.equal((await controller.checkForUpdates()).updateReady, true); assert.equal(downloads, 1);
    await controller.installUpdate(); assert.equal(installs, 0);
    allowInstall = true; await controller.installUpdate(); assert.equal(installs, 1);
});
test('signature rejection never makes an update installable', async () => {
    const controller = new LifecycleController({ platform: 'win32', packaged: true, version: '0.16.0', publishers: ['Trusted Publisher'],
        getLogin: () => false, setLogin: () => {}, readAutomaticUpdates: async () => false, writeAutomaticUpdates: async () => {},
        updater: () => ({ autoDownload: false, autoInstallOnAppQuit: false, on: () => {}, checkForUpdates: async () => ({ isUpdateAvailable: true, updateInfo: { version: '0.17.0' } }), downloadUpdate: async () => { throw new Error('Signature verification failed'); }, quitAndInstall: () => { throw new Error('must not install'); } }),
        confirmDownload: async () => true, confirmInstall: async () => true, openReleasePage: async () => {} });
    const state = await controller.checkForUpdates(); assert.equal(state.updateReady, false); assert.match(state.status, /Signature verification failed/);
    await controller.installUpdate();
});
test('packaged updater configuration must retain pinned HTTPS repository and exact publisher', async () => {
    const { validateUpdateConfiguration } = await import('../src/main/lifecycle');
    const config = { provider: 'github', owner: 'gd0306', repo: 't-cube', protocol: 'https', publisherName: ['Trusted Publisher'] };
    assert.doesNotThrow(() => validateUpdateConfiguration(config, 'Trusted Publisher'));
    for (const changed of [{ publisherName: null }, { protocol: 'http' }, { owner: 'someone' }, { private: true }, { token: 'secret' }, { publisherName: ['Someone Else'] }])
        assert.throws(() => validateUpdateConfiguration({ ...config, ...changed }, 'Trusted Publisher'));
});
test('automatic scheduler consumes state failures and still schedules the next check', async t => {
    t.mock.timers.enable({ apis: ['setTimeout'] });
    let checks = 0;
    const controller = new LifecycleController({ platform: 'win32', packaged: true, version: '0.16.0', publishers: ['Trusted Publisher'],
        getLogin: () => { throw new Error('OS state unavailable'); }, setLogin: () => {}, readAutomaticUpdates: async () => true, writeAutomaticUpdates: async () => {},
        updater: () => ({ autoDownload: false, autoInstallOnAppQuit: false, on: () => {}, checkForUpdates: async () => { checks++; return { isUpdateAvailable: false }; }, downloadUpdate: async () => {}, quitAndInstall: () => {} }),
        confirmDownload: async () => false, confirmInstall: async () => false, openReleasePage: async () => {} });
    await controller.start();
    t.mock.timers.tick(6 * 60 * 60_000); await new Promise(resolve => setImmediate(resolve));
    assert.equal(checks, 1);
    t.mock.timers.tick(6 * 60 * 60_000); await new Promise(resolve => setImmediate(resolve));
    assert.equal(checks, 2); controller.dispose();
});
test('lifecycle mutations reject non-boolean runtime inputs before OS or preference writes', async () => {
    let writes = 0;
    const controller = new LifecycleController({ platform: 'win32', packaged: true, version: '0.16.0', publishers: ['Trusted Publisher'], getLogin: () => false, setLogin: () => { writes++; }, readAutomaticUpdates: async () => false, writeAutomaticUpdates: async () => { writes++; }, updater: () => { throw new Error('unexpected updater'); }, confirmDownload: async () => false, confirmInstall: async () => false, openReleasePage: async () => {} });
    for (const value of [null, 'true', 1, {}, undefined]) {
        await assert.rejects(controller.setLoginEnabled(value as boolean), /Invalid login preference/);
        await assert.rejects(controller.setAutomaticUpdates(value as boolean), /Invalid update preference/);
    }
    assert.equal(writes, 0);
});
