/** Isolated Electron host/window/IPC smoke. Never reads/writes the system clipboard. */
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {_electron} from 'playwright';
import {mkdtemp,mkdir,writeFile,rm} from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {defaultConfiguration} from '../src/core/configuration';
const directory=await mkdtemp(path.join(os.tmpdir(),'tcube-quick-'));
const harness=path.resolve('.cache/smoke/quick-main.cjs');
await mkdir(path.dirname(harness),{recursive:true});
await writeFile(path.join(directory,'configuration.json'),JSON.stringify(defaultConfiguration()));
await build({stdin:{contents:`import {app} from 'electron';import {DesktopApplication} from './src/main/desktop';app.setName('T-Cube Quick Smoke');app.setPath('userData',process.env.TCUBE_USER_DATA_DIR!);app.on('window-all-closed',()=>{});app.whenReady().then(async()=>{const desktop=new DesktopApplication(${JSON.stringify(path.resolve('dist'))});(globalThis as any).ownedDesktop=desktop;await desktop.start();});`,resolveDir:process.cwd(),loader:'ts'},outfile:harness,bundle:true,platform:'node',target:'node22',format:'cjs',external:['electron','koffi','electron-updater']});
const app=await _electron.launch({args:[harness],env:{...process.env,TCUBE_USER_DATA_DIR:directory}});
try{
    const widget=await app.firstWindow();await widget.waitForURL('**/widget.html');
    await app.evaluate(async()=>{await (globalThis as any).ownedDesktop.office.showClipboardQuick();});
    const quick=app.windows().find(page=>page.url().endsWith('clipboard-quick.html'))!;
    assert.ok(quick);await quick.getByRole('button',{name:'启用记录',exact:true}).waitFor();
    assert.equal((await quick.evaluate(()=>window.tcube.getClipboardHistory())).isEnabled,false);
    await assert.rejects(quick.evaluate(()=>window.tcube.getLibrary()),/authorized/);
    await quick.keyboard.press('Escape');
    assert.equal(await app.evaluate(()=> (globalThis as any).ownedDesktop.office.quickWindow.isVisible()),false);
    await app.evaluate(async()=>{await (globalThis as any).ownedDesktop.office.showClipboardQuick();});
    assert.equal((await quick.evaluate(()=>window.tcube.getClipboardHistory())).isEnabled,false);
    await quick.screenshot({path:'.cache/smoke/clipboard-quick-electron-empty.png'});
    await quick.getByRole('button',{name:'完整历史管理',exact:true}).click();
    await app.evaluate(()=>new Promise<void>(resolve=>setTimeout(resolve,200)));
    assert.equal(await app.evaluate(()=> (globalThis as any).ownedDesktop.office.quickWindow.isVisible()),false);
    const library=app.windows().find(page=>page.url().endsWith('library.html'))!;assert.ok(library);
    assert.equal(await library.locator('#history-panel').isVisible(),true);
    console.log('Isolated Electron production host: paused quick window, role rejection, Escape dismissal, reopen and full-manager transition passed; no system clipboard touched.');
}finally{await app.close();await rm(directory,{recursive:true,force:true});}
