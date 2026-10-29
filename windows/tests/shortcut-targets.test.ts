import test from 'node:test';
import assert from 'node:assert/strict';
import { defaultConfiguration, normalizeConfiguration } from '../src/core/configuration';
import { validateLocalTarget } from '../src/main/targets';
import { scanBrokenLaunchers } from '../src/main/maintenance';
import { validateArchive } from '../src/core/configuration-archive';

test('files and safe URL targets survive configuration and backup decoding', () => {
    const config = defaultConfiguration();
    config.groups.front.slots = [
        { id: 'file', name: 'Notes', kind: 'file', path: 'C:\\Notes\\brief.pdf' },
        { id: 'web', name: 'Docs', kind: 'website', path: 'https://example.com/Docs?q=Cube#start' },
        { id: 'settings', name: 'Wi-Fi', kind: 'systemSettings', path: 'ms-settings:network-wifi' }, null,
    ];
    assert.deepEqual(normalizeConfiguration(config), config);
    const archive = validateArchive({ version: 1, createdAt: new Date().toISOString(), configuration: config, contentLibrary: { version: 1, items: [] } });
    assert.deepEqual(archive.configuration.groups.front.slots, config.groups.front.slots);
});

test('URL targets reject unsafe schemes, credentials, malformed hosts and wrong kind pairs', async () => {
    const { validateTarget } = await import('../src/main/targets');
    for (const path of ['javascript:alert(1)', 'file:///C:/x', 'ftp://example.com', 'https://user:pass@example.com', 'https://user@example.com', 'https:///example.com', 'https://', 'https://example.com\\x', 'https://example.com\n/x', ' https://example.com', 'https://@example.com']) {
        await assert.rejects(validateTarget(path, 'website'), /website|URL/i, path);
    }
    for (const path of ['ms-settings:network-wifi?x=1', 'ms-settings:network-wifi/', 'ms-settings:unknown', 'MS-SETTINGS:network-wifi', 'https://example.com']) {
        await assert.rejects(validateTarget(path, 'systemSettings'), /settings/i, path);
    }
    for (const [kind, path] of [['file', 'https://example.com'], ['website', 'C:\\Tools\\x.exe'], ['application', 'ms-settings:display']] as const) {
        const config = defaultConfiguration();
        config.groups.front.slots[0] = { id: 'bad', name: 'Bad', kind, path };
        assert.throws(() => normalizeConfiguration(config));
    }
});

test('URL path case remains significant while duplicate host spelling is normalized', () => {
    const config = defaultConfiguration();
    config.groups.front.slots[0] = { id: 'one', name: 'One', kind: 'website', path: 'https://example.com/Docs' };
    config.groups.front.slots[1] = { id: 'two', name: 'Two', kind: 'website', path: 'https://EXAMPLE.com/docs' };
    assert.doesNotThrow(() => normalizeConfiguration(config));
    config.groups.front.slots[1]!.path = 'https://EXAMPLE.com/Docs';
    assert.throws(() => normalizeConfiguration(config), /Duplicate/);
});

test('files use local filesystem validation and URLs skip filesystem scanning', async () => {
    const stat = async () => ({ isFile: () => true, isDirectory: () => false });
    assert.equal((await validateLocalTarget('C:\\Notes\\brief.pdf', 'file', stat)).kind, 'file');
    assert.equal((await validateLocalTarget('C:\\Notes\\brief.pdf', undefined, stat)).kind, 'file');
    await assert.rejects(validateLocalTarget('C:\\Notes\\brief.pdf', 'application', stat));
    const config = defaultConfiguration();
    config.groups.front.slots[0] = { id: 'web', name: 'Docs', kind: 'website', path: 'https://example.com' };
    config.groups.front.slots[1] = { id: 'settings', name: 'Display', kind: 'systemSettings', path: 'ms-settings:display' };
    let called = 0;
    assert.deepEqual(await scanBrokenLaunchers(config, async () => { called++; throw Error('filesystem unavailable'); }), []);
    assert.equal(called, 0);
});

test('icon cache supplies local URL artwork without extracting filesystem icons', async () => {
    const { IconCache } = await import('../src/main/icons');
    const config = defaultConfiguration();
    config.groups.front.slots[0] = { id: 'web', name: 'Docs', kind: 'website', path: 'https://example.com' };
    config.groups.front.slots[1] = { id: 'settings', name: 'Display', kind: 'systemSettings', path: 'ms-settings:display' };
    const icons = await new IconCache().forConfiguration(config);
    assert.match(icons.web, /^data:image\/svg\+xml/);
    assert.match(icons.settings, /^data:image\/svg\+xml/);
    assert.notEqual(icons.web, icons.settings);
});

test('macOS preview never passes stored Windows paths into its native icon extraction', async () => {
    const { isLocalIconPath } = await import('../src/main/targets');
    assert.equal(isLocalIconPath('C:\\Preview\\Editor.exe', 'darwin'), false);
});
