import assert from 'node:assert/strict';
import { spawn, type ChildProcess } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { appendFile, mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import koffi from 'koffi';
import type { ElectronApplication, Page } from 'playwright';
import type { TextSnippet } from '../src/shared/productivity';

function withDeadline<T>(pending:Promise<T>,label:string,milliseconds=10000):Promise<T> {
    let timer:ReturnType<typeof setTimeout>;
    return Promise.race([pending,new Promise<never>((_resolve,reject)=>{timer=setTimeout(()=>reject(new Error(`${label} timed out`)),milliseconds);})]).finally(()=>clearTimeout(timer));
}

async function until<T>(read: () => Promise<T>, check: (value: T) => boolean, message: string, timeout = 10_000): Promise<T> {
    const deadline = Date.now() + timeout;
    let last: T | undefined;
    do {
        last = await withDeadline(read(),message);
        if (check(last)) return last;
        await new Promise(resolve => setTimeout(resolve, 50));
    } while (Date.now() < deadline);
    throw new Error(`${message}: ${String(last).slice(0, 500)}`);
}

/** Windows CI only: copies through the real UI and pastes exclusively into an owned WinForms receiver. */
export async function verifyLibrarySmoke(app: ElectronApplication, widget: Page): Promise<string[]> {
    if (process.platform !== 'win32') return ['Native office-library smoke skipped on macOS preview.'];
    const isolated = await app.evaluate(({ app }) => ({ actual: app.getPath('userData'), expected: process.env.TCUBE_USER_DATA_DIR }));
    assert.ok(isolated.expected, 'Office smoke requires TCUBE_USER_DATA_DIR');
    assert.equal(path.resolve(isolated.actual), path.resolve(isolated.expected), 'Office smoke may only edit isolated CI data');
    const user = koffi.load('user32.dll');
    const find = user.func('uintptr_t __stdcall FindWindowW(str16 className, str16 title)');
    const foreground = user.func('uintptr_t __stdcall GetForegroundWindow()');
    const activate = user.func('int __stdcall SetForegroundWindow(uintptr_t window)');
    const child = user.func('uintptr_t __stdcall GetWindow(uintptr_t window, uint32_t command)');
    const processForWindow = user.func('uint32_t __stdcall GetWindowThreadProcessId(uintptr_t window, _Out_ uint32_t *process)');
    const getTitle = user.func('int __stdcall GetWindowTextW(uintptr_t window, _Out_ void *text, int count)');
    const getClass = user.func('int __stdcall GetClassNameW(uintptr_t window, _Out_ void *text, int count)');
    const message = user.func('intptr_t __stdcall SendMessageTimeoutW(uintptr_t window, uint32_t message, uintptr_t count, void *text, uint32_t flags, uint32_t timeout, _Out_ uintptr_t *result)');
    const post = user.func('int __stdcall PostMessageW(uintptr_t window, uint32_t message, uintptr_t wParam, intptr_t lParam)');
    const title = `T-Cube owned paste receiver ${randomUUID()}`;
    const clipboardKey = `tcubeOfficeClipboard_${randomUUID().replaceAll('-', '')}`;
    const snippet: TextSnippet = {
        id: randomUUID(), title: `办公资料 smoke ${randomUUID().slice(0, 8)}`, group: 'Smoke / 办公',
        body: 'T-Cube native paste verification', isFavorite: true,
        fields: [{ id: randomUUID(), label: '邮箱', value: `office-${randomUUID().slice(0, 8)}@example.test` }],
    };
    const fullText = `${snippet.body}\n邮箱：${snippet.fields[0].value}`;
    let receiver: ChildProcess | undefined, receiverWindow = 0n, textbox = 0n, library: Page | undefined;
    let clipboardSaved = false, fixtureSaved = false, failed = false, receiverError = '';
    const results: string[] = [];
    function owns(window: bigint): boolean {
        const pid = [0];
        return Boolean(window && receiver?.pid && processForWindow(window, pid) && pid[0] === receiver.pid);
    }
    function receiverText(): string {
        assert.ok(owns(receiverWindow) && owns(textbox), 'Receiver handles must still belong to the spawned process');
        const buffer = Buffer.alloc(32768), result = [0];
        // GetWindowTextW deliberately cannot retrieve another process's edit-control text.
        // WM_GETTEXT is a system message; Windows safely marshals this bounded buffer.
        assert.ok(message(textbox, 0x000d, buffer.length / 2, buffer, 0x0002, 1000, result), 'Owned receiver WM_GETTEXT timed out');
        return buffer.toString('utf16le').split('\0')[0].replace(/\r\n/g, '\n');
    }
    async function capture(name: string) {
        if (!library) return;
        const png = await app.evaluate(async ({ BrowserWindow }, url) => {
            const window = BrowserWindow.getAllWindows().find(candidate => candidate.webContents.getURL() === url);
            if (!window) throw new Error('Library disappeared before capture');
            return (await window.webContents.capturePage()).toPNG().toString('base64');
        }, library.url());
        await mkdir(path.resolve('.cache/smoke'), { recursive: true });
        await writeFile(path.resolve('.cache/smoke', name), Buffer.from(png, 'base64'));
    }
    async function showLibrary(): Promise<Page> {
        await withDeadline(widget.evaluate(() => window.tcube.showLibrary()),'showLibrary native focus capture');
        const pages = await until(async () => app.windows(), pages => pages.some(page => page.url().endsWith('/library.html')), 'Library window missing');
        const page = pages.find(page => page.url().endsWith('/library.html'))!;
        await page.waitForLoadState('domcontentloaded');
        return page;
    }
    const stage = async (name:string) => { console.log(`Office smoke: ${name}`); await appendFile(path.resolve('.cache/smoke/office-progress.txt'),`${new Date().toISOString()} ${name}\n`); };
    try {
        await stage('snapshot clipboard');
        await app.evaluate(async ({ clipboard, ClipboardItem }, key) => {
            // Materialize every format before changing the clipboard; keep native items in main.
            const items = await clipboard.read();
            const snapshot = await Promise.all(items.filter(item => item.types.length > 0).map(async item => new ClipboardItem(Object.fromEntries(await Promise.all(item.types.map(async type => [type, await item.getType(type)] as const))))));
            (globalThis as unknown as Record<string, unknown>)[key] = snapshot;
        }, clipboardKey);
        clipboardSaved = true;
        await stage('create library fixture');
        library = await showLibrary();
        library.setDefaultTimeout(15000);
        await library.evaluate(item => window.tcube.saveSnippet(item), snippet);
        fixtureSaved = true;
        // Reload through the actual capture/show path, then select the stored fixture.
        await stage('reload library');
        await library.reload();
        await library.locator('#search').fill(snippet.title);
        await library.getByRole('button', { name: new RegExp(snippet.title) }).click();
        await library.getByRole('heading', { name: snippet.title, exact: true }).waitFor();
        await capture('office-library-structured.png');
        await stage('copy text');
        await library.getByRole('button', { name: '复制全部', exact: true }).click();
        await until(() => app.evaluate(async ({ clipboard }) => clipboard.readText()), text => text === fullText, 'Whole-snippet copy did not reach clipboard');
        await library.getByRole('button', { name: `复制字段：${snippet.fields[0].label}`, exact: true }).click();
        await until(() => app.evaluate(async ({ clipboard }) => clipboard.readText()), text => text === snippet.fields[0].value, 'Field copy did not reach clipboard');
        results.push('Structured office snippet rendered with real whole-text and individual-field copy buttons.');

        // The next showLibrary call captures only when the panel is hidden.
        await app.evaluate(({ BrowserWindow }, url) => BrowserWindow.getAllWindows().find(window => window.webContents.getURL() === url)?.hide(), library.url());
        await stage('spawn owned receiver');
        const command = `
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$form = New-Object System.Windows.Forms.Form
$form.Text = '${title}'
$form.Width = 640
$form.Height = 260
$form.StartPosition = 'CenterScreen'
$box = New-Object System.Windows.Forms.TextBox
$box.Multiline = $true
$box.AcceptsReturn = $true
$box.Dock = 'Fill'
$form.Controls.Add($box)
$form.Add_Shown({ $form.Activate(); $box.Focus() | Out-Null })
[System.Windows.Forms.Application]::Run($form)
$form.Dispose()
`;
        receiver = spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-STA', '-EncodedCommand', Buffer.from(command, 'utf16le').toString('base64')], { windowsHide: false, stdio: ['ignore', 'ignore', 'pipe'] });
        receiver.on('error', error => { receiverError = error.message; });
        receiver.stderr?.on('data', chunk => { receiverError += String(chunk).slice(0, 4000); });
        await stage('find receiver window');
        receiverWindow = await until(async () => {
            if (!receiver!.pid && receiverError) throw new Error(`Owned paste receiver failed: ${receiverError}`);
            if (receiver!.exitCode !== null) throw new Error(`Owned paste receiver exited (${receiver!.exitCode}): ${receiverError}`);
            return BigInt(find(null, title));
        }, value => value !== 0n, 'Owned WinForms receiver did not appear');
        await stage('validate receiver PID');
        assert.ok(owns(receiverWindow), 'Receiver Form PID must match spawned PowerShell');
        await stage('read receiver title');
        const titleBuffer = Buffer.alloc(1024); getTitle(receiverWindow, titleBuffer, 512);
        assert.equal(titleBuffer.toString('utf16le').split('\0')[0], title);
        await stage('find receiver textbox');
        textbox = BigInt(child(receiverWindow, 5)); // GW_CHILD: the Form owns exactly one TextBox.
        assert.ok(owns(textbox), 'TextBox must belong to owned receiver');
        await stage('read receiver class');
        const classBuffer = Buffer.alloc(1024); getClass(textbox, classBuffer, 512);
        assert.match(classBuffer.toString('utf16le').split('\0')[0], /^WindowsForms10\.EDIT/i, 'Receiver child must be an edit control');
        await stage('activate receiver');
        activate(receiverWindow);
        await until(async () => BigInt(foreground()), value => value === receiverWindow, 'Owned receiver could not become foreground');
        await stage('show library with receiver target');
        library = await showLibrary(); // evaluate does not activate the widget; capture the external TextBox.
        await stage('paste whole text');
        await library.getByRole('button', { name: '粘贴全部', exact: true }).click();
        await until(async () => receiverText(), text => text === fullText, 'Native whole-text Ctrl+V did not populate owned receiver');
        assert.equal(BigInt(foreground()), receiverWindow, 'Paste must return foreground to original receiver');
        results.push('Native Windows paste restored the original WinForms TextBox and inserted the full structured text without submitting.');
        library = await showLibrary();
        await stage('paste field');
        await library.getByRole('button', { name: `粘贴字段：${snippet.fields[0].label}`, exact: true }).click();
        await until(async () => receiverText(), text => text === `${fullText}${snippet.fields[0].value}`, 'Native individual-field Ctrl+V did not append into owned receiver');
        assert.equal(BigInt(foreground()), receiverWindow);
        results.push('Native individual-field paste reused the captured input field and kept the owned receiver open.');
        return results;
    } catch (error) {
        failed = true;
        await writeFile(path.resolve('.cache/smoke/office-error.txt'),error instanceof Error?error.stack??error.message:String(error));
        await withDeadline(capture('office-library-failure.png'),'failure capture',5000).catch(() => undefined);
        throw error;
    } finally {
        await stage('cleanup');
        const cleanupErrors: unknown[] = [];
        const clean = async (action: () => unknown) => { try { await action(); } catch (error) { cleanupErrors.push(error); } };
        if (receiver) await clean(async () => {
            await stage('cleanup receiver');
            if (owns(receiverWindow)) post(receiverWindow, 0x0010, 0, 0); // WM_CLOSE, owned PID only.
            const deadline = Date.now() + 2000;
            while (receiver!.exitCode === null && receiver!.signalCode === null && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 50));
            if (receiver!.exitCode === null && receiver!.signalCode === null) receiver!.kill();
        });
        await stage('cleanup fixture');
        if (fixtureSaved && library && !library.isClosed()) await clean(() => library!.evaluate(id => window.tcube.deleteSnippet(id), snippet.id));
        if (library && !library.isClosed()) await clean(() => app.evaluate(({ BrowserWindow }, url) => BrowserWindow.getAllWindows().find(window => window.webContents.getURL() === url)?.hide(), library!.url()));
        await stage('restore clipboard');
        if (clipboardSaved) await clean(() => app.evaluate(async ({ clipboard }, key) => {
            const state = globalThis as unknown as Record<string, unknown>;
            const snapshot = state[key] as Electron.ClipboardItem[];
            try { if (snapshot.length) await clipboard.write(snapshot); else clipboard.clear(); }
            finally { delete state[key]; }
        }, clipboardKey));
        if (cleanupErrors.length) {
            const error = new AggregateError(cleanupErrors, 'Office smoke cleanup failed');
            if (failed) console.error(error); else throw error;
        }
    }
}
