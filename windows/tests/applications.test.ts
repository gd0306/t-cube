import assert from 'node:assert/strict';
import { test } from 'node:test';
import { InstalledApplications, normalizeApplications } from '../src/main/applications';

test('registered apps are normalized, deduplicated and exclude non-launchable files', () => {
    const apps = normalizeApplications([
        { name: 'Editor', path: 'C:\\Apps\\Editor.exe' },
        { name: 'Duplicate', path: 'c:/apps/editor.EXE' },
        { name: 'Calculator', path: 'Microsoft.WindowsCalculator_abc!App' },
        { name: 'Documentation', path: 'C:\\Apps\\help.chm' },
        { name: 'Uninstall', path: 'C:\\Apps\\unins000.exe' },
        { name: 'Remote', path: '\\\\server\\app.exe' },
        { name: 'Injected', path: 'App & calc.exe' },
        { name: 'Link', path: 'C:\\Menu\\App.lnk', target: 'C:\\Other\\App.exe' },
    ]);
    assert.equal(apps.length, 3);
    assert.deepEqual(
        new Set(apps.map((app) => app.name)),
        new Set(['Editor', 'Calculator', 'Link']),
    );
    assert.equal(apps.find((app) => app.name === 'Calculator')!.kind, 'shell');
    assert.equal(
        normalizeApplications([{ name: 'Editor', path: 'C:\\Apps\\Editor.exe' }])[0].id,
        apps.find((app) => app.name === 'Editor')!.id,
    );
});

test('shortcuts retain launch context while exact executable and app-ID aliases are deduplicated', () => {
    const apps = normalizeApplications([
        { name: 'Editor executable', path: 'C:\\Apps\\Editor.exe' },
        { name: 'Editor', path: 'Vendor.Editor' },
        {
            name: 'Editor',
            path: 'C:\\Menu\\Editor.lnk',
            target: 'C:\\Apps\\Editor.exe',
            arguments: '',
            workingDirectory: 'C:\\Workspace',
            appId: 'Vendor.Editor',
        },
        {
            name: 'Duplicate link',
            path: 'C:\\OtherMenu\\Editor.lnk',
            target: 'C:\\Apps\\Editor.exe',
            arguments: '',
            workingDirectory: 'C:\\Workspace',
        },
        {
            name: 'Another workspace',
            path: 'C:\\Menu\\Editor2.lnk',
            target: 'C:\\Apps\\Editor.exe',
            arguments: '',
            workingDirectory: 'C:\\Workspace2',
        },
        { name: 'Folder link', path: 'C:\\Menu\\Tools.lnk', target: 'C:\\Tools' },
        {
            name: 'Uninstaller link',
            path: 'C:\\Menu\\Remove.lnk',
            target: 'C:\\Apps\\uninstall.exe',
        },
    ]);
    assert.deepEqual(
        apps.map((app) => app.path).sort(),
        ['C:\\Menu\\Editor.lnk', 'C:\\Menu\\Editor2.lnk'].sort(),
    );
});

test('Windows short-path aliases do not bypass preference for the original shortcut', () => {
    const apps = normalizeApplications([
        {
            name: 'App',
            path: 'C:\\PROGRA~1\\Editor\\App.exe',
            canonicalPath: 'C:\\Program Files\\Editor\\App.exe',
        },
        {
            name: 'App',
            path: 'C:\\Menu\\App.lnk',
            target: 'C:\\Program Files\\Editor\\App.exe',
            workingDirectory: 'C:\\Workspace',
        },
    ]);
    assert.deepEqual(
        apps.map((app) => app.path),
        ['C:\\Menu\\App.lnk'],
    );
});

test('discovery shares in-flight work, caches results and refreshes explicitly', async () => {
    let calls = 0;
    const catalog = new InstalledApplications({
        query: async () => {
            calls++;
            return [{ name: 'Editor', path: 'C:\\Editor.exe' }];
        },
        validate: async (path) => ({ id: 'target', name: 'File name', path, kind: 'application' }),
        shortcut: async () => {
            throw Error('unused');
        },
        icon: async () => null,
    });
    await Promise.all([catalog.list(), catalog.list()]);
    await catalog.list();
    assert.equal(calls, 1);
    await catalog.list(true);
    assert.equal(calls, 2);
});

test('selection accepts a catalog ID, revalidates paths and preserves the display name', async () => {
    const paths: string[] = [];
    let generated = 0;
    const catalog = new InstalledApplications({
        query: async () => [
            { name: 'My Editor', path: 'C:\\Editor.exe' },
            { name: 'Calculator', path: 'Vendor.Calculator!App' },
        ],
        validate: async (path) => {
            paths.push(path);
            return { id: 'new', name: 'Filename', path, kind: 'application' };
        },
        shortcut: async (candidate) => {
            generated++;
            assert.equal(candidate.path, 'Vendor.Calculator!App');
            return 'C:\\T-Cube\\apps\\calculator.lnk';
        },
        icon: async () => 'data:image/png;base64,AA==',
    });
    const apps = await catalog.list();
    assert.equal(
        (await catalog.materialize(apps.find((app) => app.name === 'My Editor')!.id)).name,
        'My Editor',
    );
    assert.equal(
        (await catalog.materialize(apps.find((app) => app.name === 'Calculator')!.id)).path,
        'C:\\T-Cube\\apps\\calculator.lnk',
    );
    assert.equal(generated, 1);
    await assert.rejects(catalog.materialize('C:\\Arbitrary.exe'), /列表/);
    assert.deepEqual(paths, ['C:\\Editor.exe', 'C:\\T-Cube\\apps\\calculator.lnk']);
    assert.deepEqual(Object.keys(await catalog.icons([apps[0].id])), [apps[0].id]);
    await assert.rejects(catalog.icons(Array(33).fill(apps[0].id)), /图标/);
});

test('a failed refresh preserves valid entries and retries discovery later', async () => {
    let fails = false;
    const catalog = new InstalledApplications({
        query: async () => {
            if (fails) throw Error('discovery unavailable');
            return [{ name: 'App', path: 'C:\\App.exe' }];
        },
        validate: async (path) => ({ id: 'new', name: 'App', path, kind: 'application' }),
        shortcut: async () => '',
        icon: async () => null,
    });
    const [app] = await catalog.list();
    fails = true;
    await assert.rejects(catalog.list(true), /unavailable/);
    assert.equal((await catalog.materialize(app.id)).name, 'App');
});

test('browsing beyond the icon budget reloads the least-recently-used icon and retains a recently viewed icon', async () => {
    const loads = new Map<string, number>();
    const catalog = new InstalledApplications({
        query: async () => Array.from({ length: 258 }, (_, index) => ({ name: `App ${index}`, path: `C:\\Apps\\App${index}.exe` })),
        validate: async path => ({ id: path, name: path, path, kind: 'application' }),
        shortcut: async () => { throw Error('unused'); },
        icon: async entry => {
            const version = (loads.get(entry.id) ?? 0) + 1;
            loads.set(entry.id, version);
            return `data:${entry.name}:${version}`;
        },
    });
    const entries = await catalog.list();
    for (let index = 0; index < 256; index += 32) await catalog.icons(entries.slice(index, index + 32).map(entry => entry.id));
    await catalog.icons([entries[0].id]); // Touch the oldest entry before another application is viewed.
    await catalog.icons([entries[256].id]);
    assert.equal((await catalog.icons([entries[0].id]))[entries[0].id], 'data:App 0:1');
    assert.equal((await catalog.icons([entries[1].id]))[entries[1].id], 'data:App 1:2');
});

test('successful discovery refresh releases pending shell images and removes uninstalled applications', async () => {
    const { AsyncResourceCache } = await import('../src/main/resource-cache');
    const nativeImages = new AsyncResourceCache<string>(32, false);
    let records = [{ name: 'Calculator', path: 'Vendor.Calculator!App' }, { name: 'Editor', path: 'C:\\Editor.exe' }];
    const finish: Array<(value: string) => void> = [];
    const catalog = new InstalledApplications({
        query: async () => records,
        validate: async path => ({ id: path, name: path, path, kind: 'application' }),
        shortcut: async () => { throw Error('unused'); },
        icon: entry => nativeImages.getOrLoad(entry.id, () => new Promise(resolve => { finish.push(resolve); })),
        clearIconResources: () => nativeImages.clear(),
    });
    const entries = await catalog.list(), calculator = entries.find(entry => entry.name === 'Calculator')!, editor = entries.find(entry => entry.name === 'Editor')!;
    const old = catalog.icons([calculator.id]);
    records = [{ name: 'Calculator', path: 'Vendor.Calculator!App' }];
    await catalog.list(true);
    const refreshed = catalog.icons([calculator.id]);
    finish[0]('old shell pixels');
    finish[1]?.('fresh shell pixels');
    assert.deepEqual(await old, { [calculator.id]: 'old shell pixels' });
    assert.deepEqual(await refreshed, { [calculator.id]: 'fresh shell pixels' });
    assert.deepEqual(await catalog.icons([editor.id]), {});
    await assert.rejects(catalog.materialize(editor.id), /列表/);
});

test('failed discovery refresh preserves cached icons until a valid replacement catalog is available', async () => {
    let failure: 'none' | 'query' | 'invalid' = 'none', iconVersion = 0;
    const catalog = new InstalledApplications({
        query: async () => {
            if (failure === 'query') throw Error('offline');
            return failure === 'invalid' ? null : [{ name: 'Editor', path: 'C:\\Editor.exe' }];
        },
        validate: async path => ({ id: path, name: path, path, kind: 'application' }),
        shortcut: async () => { throw Error('unused'); },
        icon: async () => `pixels ${++iconVersion}`,
    });
    const [entry] = await catalog.list();
    assert.deepEqual(await catalog.icons([entry.id]), { [entry.id]: 'pixels 1' });
    for (const mode of ['query', 'invalid'] as const) {
        failure = mode;
        await assert.rejects(catalog.list(true));
        assert.deepEqual(await catalog.icons([entry.id]), { [entry.id]: 'pixels 1' });
    }
    failure = 'none';
    await catalog.list(true);
    assert.deepEqual(await catalog.icons([entry.id]), { [entry.id]: 'pixels 2' });
});
