import { BrowserWindow, ipcMain, screen, type Tray } from 'electron';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DisplayInputService } from './display-input-service';
import { handleDisplayInputRequest, isPanelSender } from './display-input-ipc';
export class DisplayInputPanel {
    private window: BrowserWindow | null = null;
    constructor(private readonly directory: string, private readonly service: DisplayInputService) {
        for (const channel of ['list', 'save', 'switch', 'close'] as const) ipcMain.handle(`display-input:${channel}`, async (event, payload: unknown) => {
            const window = this.window;
            const authorized = isPanelSender(window, event.sender, event.senderFrame);
            return handleDisplayInputRequest(channel, authorized, payload, {
                list: () => this.service.list(), save: (identity, mapping) => this.service.save(identity, mapping),
                switch: (identity, target) => this.service.switch(identity, target), close: () => window?.close()
            });
        });
    }
    show(tray: Tray): void {
        if (this.window && !this.window.isDestroyed()) { this.window.show(); this.window.focus(); this.window.webContents.send('display-input:displays-changed'); return; }
        const bounds = tray.getBounds(); const work = screen.getDisplayNearestPoint({ x: bounds.x, y: bounds.y }).workArea;
        const width = 400, height = 520;
        const x = Math.max(work.x, Math.min(work.x + work.width - width, bounds.x + bounds.width - width));
        const y = Math.max(work.y, Math.min(work.y + work.height - height, bounds.y - height));
        const window = this.window = new BrowserWindow({ x, y, width, height, show: false, resizable: false, autoHideMenuBar: true, skipTaskbar: true,
            title: '显示器输入源', webPreferences: { preload: path.join(this.directory, 'display-input-preload.cjs'), sandbox: true, contextIsolation: true, nodeIntegration: false, webSecurity: true, webviewTag: false, partition: 'display-input-panel' } });
        window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
        window.webContents.on('will-navigate', event => event.preventDefault());
        window.webContents.session.webRequest.onBeforeRequest((details, callback) => {
            const allowed = new Set(['display-input.html', 'display-input.js', 'display-input.css']);
            const root = path.join(this.directory, 'renderer');
            let permit = false;
            try { const url = new URL(details.url); const file = fileURLToPath(url); permit = url.protocol === 'file:' && path.dirname(file) === root && allowed.has(path.basename(file)); } catch {}
            callback({ cancel: !permit });
        });
        window.webContents.session.setPermissionRequestHandler((_contents, _permission, callback) => callback(false));
        window.on('closed', () => { this.service.cancel(); if (this.window === window) this.window = null; });
        void window.loadFile(path.join(this.directory, 'renderer', 'display-input.html')).then(() => { if (!window.isDestroyed()) window.show(); });
    }
    cancel(): void {
        this.service.cancel();
        if (this.window && !this.window.isDestroyed()) this.window.webContents.send('display-input:displays-changed');
    }
    whenIdle(): Promise<unknown> { return this.service.whenIdle(); }
    dispose(): void { this.service.cancel(); this.window?.destroy(); this.window = null; for (const channel of ['list', 'save', 'switch', 'close']) ipcMain.removeHandler(`display-input:${channel}`); }
}
