import test from 'node:test';
import assert from 'node:assert/strict';
import { defaultConfiguration } from '../src/core/configuration';
import { scanBrokenLaunchers } from '../src/main/maintenance';
import { validateLocalTarget } from '../src/main/targets';

test('launcher scan detects existing paths that changed between executable and folder', async () => {
    const config = defaultConfiguration();
    config.groups.front.slots[0] = { id: 'app', path: 'C:\\Tools\\changed.exe', name: 'Changed App', kind: 'application' };
    config.groups.front.slots[1] = { id: 'folder', path: 'C:\\Tools\\folder.exe', name: 'Changed Folder', kind: 'folder' };
    config.groups.front.slots[2] = { id: 'good', path: 'C:\\Tools\\good.exe', name: 'Good App', kind: 'application' };
    const broken = await scanBrokenLaunchers(config, (path, kind) => validateLocalTarget(path, kind, async value => ({ isDirectory: () => value.endsWith('changed.exe'), isFile: () => !value.endsWith('changed.exe') })));
    assert.deepEqual(broken.map(item => item.name), ['Changed App', 'Changed Folder']);
});
test('maintenance rejects malformed repair and import arguments before callbacks or dialogs', async () => {
    const { MaintenanceService } = await import('../src/main/maintenance');
    const service = new MaintenanceService({ configurationPath: '/unused/configuration.json', libraryPath: '/unused/content-library.json', getConfiguration: defaultConfiguration, afterRestore: async () => { throw new Error('unexpected restore'); }, repairLauncher: async () => { throw new Error('unexpected repair'); } });
    await assert.rejects(service.repairLauncher(null as never), /Invalid launcher/);
    await assert.rejects(service.repairLauncher({ face: 'front', slot: 4 }), /Invalid launcher/);
    await assert.rejects(service.previewImportBackup(null as never), /Invalid backup ID/);
    await assert.rejects(service.confirmImportBackup(null as never), /Invalid import token/);
});
