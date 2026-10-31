import {OfficeServices} from './office-services';
import {DisplayPositionStore} from './display-position-store';
import { app, BrowserWindow, dialog, ipcMain, Menu, nativeImage, screen, shell, Tray } from 'electron';
import type { BrowserWindowConstructorOptions } from 'electron';
import { access } from 'node:fs/promises';
import path from 'node:path';
import { ConfigurationStore } from '../core/store';
import { readInputState, readReducedMotion } from '../native/win32';
import type { Face, Placement, Rect } from '../shared/contracts';
import { LauncherHost } from './application';
import { IconCache } from './icons';
import { CHANNELS, registerIPC } from './ipc';
import type { WindowRole } from './ipc';
import { validateTarget } from './targets';
import { createApplicationCatalog } from './application-discovery';

export function userDataDirectory(platform: string, appData: string, override = process.env.TCUBE_USER_DATA_DIR): string {
    return override ? path.resolve(override) : path.join(appData, platform === 'darwin' ? 'T-Cube-Windows-Preview' : 'T-Cube');
}

/** Owns desktop resources; LauncherHost owns all configuration and gesture decisions. */
export class DesktopApplication {
    host!: LauncherHost;
    widget!: BrowserWindow;
    settings: BrowserWindow | null = null;
    expanded: BrowserWindow | null = null;
    private tray: Tray | null = null;
    private roles = new Map<number, WindowRole>();
    private timer: NodeJS.Timeout | null = null;
    private quitting = false;
    private quitCancelled: (() => void) | null = null;
    private pollActive = false;
    private previousButtons = false;
    private readonly iconCache = new IconCache();
    private readonly started = Date.now();
    private office: OfficeServices | null = null;
    private whenLauncherOperationsIdle: () => Promise<void> = async () => {};
    private reducedMotion = false;
    private preferenceSample = 0;
    constructor(readonly directory = __dirname) {}
    async start(): Promise<void> {
        const file = path.join(app.getPath('userData'), 'configuration.json');
        const firstLaunch = await access(file).then(() => false, error => {
            if (error.code === 'ENOENT') return true;
            throw error;
        });
        const store = new ConfigurationStore(file);
        try { await store.load(); }
        catch (error) {
            const answer = await dialog.showMessageBox({ type: 'error', title: 'T-Cube configuration',
                message: 'The configuration could not be read.',
                detail: `${String(error)}\n\nBack up the existing file and reset to defaults? The original bytes will be preserved in a .backup file.`,
                buttons: ['Cancel', 'Back up and reset'], defaultId: 0, cancelId: 0, noLink: true });
            if (answer.response !== 1) { app.quit(); return; }
            await store.backupAndReset();
        }
        this.widget = this.createWindow('widget', { title: 'T-Cube', width: 164, height: 164, frame: false,
            transparent: true, backgroundColor: '#00000000', resizable: false, hasShadow: false,
            focusable: process.platform !== 'win32', skipTaskbar: true, alwaysOnTop: true, thickFrame: false });
        this.host = new LauncherHost(store, {
            platform: process.platform, cursor: () => screen.getCursorScreenPoint(), input: readInputState,
            screens: () => screen.getAllDisplays().map(display => display.workArea),
            displays: () => {
                const primary = screen.getPrimaryDisplay().id;
                return screen.getAllDisplays().sort((a,b) => Number(b.id === primary)-Number(a.id === primary)).map(display => ({id:String(display.id),workArea:display.workArea}));
            },
            displayPositions: new DisplayPositionStore(path.join(app.getPath('userData'),'display-positions.json')),
            setFrame: frame => this.widget.setBounds(this.roundFrame(frame), false),
            setVisible: visible => { if (visible) this.widget.show(); else this.widget.hide(); this.updateTray(); },
            openPath: target => shell.openPath(target),
            openExternal: url => shell.openExternal(url),
            showSettings: () => this.showSettings(), showExpanded: face => this.showExpanded(face),
            closeExpanded: () => this.expanded?.hide(),
            stateChanged: state => this.broadcast(CHANNELS.state, state),
            iconsChanged: icons => this.broadcast(CHANNELS.icons, icons), error: message => this.broadcast(CHANNELS.error, message),
            validateTarget,
            chooseTarget: async request => {
                const options: Electron.OpenDialogOptions = request.kind === 'folder'
                    ? { title: '选择文件夹', properties: ['openDirectory'] }
                    : request.kind === 'file' ? { title: '选择文件', properties: ['openFile'] }
                    : { title: '选择应用程序文件', properties: ['openFile'], filters: [{ name: '应用程序', extensions: ['exe'] }, { name: '快捷方式', extensions: ['lnk'] }] };
                const result = await dialog.showOpenDialog(this.settings ?? this.widget, options);
                return result.canceled ? [] : result.filePaths;
            },
            quit: () => app.quit(), refreshIcons: config => this.iconCache.forConfiguration(config)
        });
        await this.host.initializeDisplayPositions().catch(error => {
            void dialog.showMessageBox({type:'warning',message:'显示器位置记忆暂不可用，原文件已保留。',detail:String(error),buttons:['继续']});
        });
        this.office = new OfficeServices({host:this.host,directory:app.getPath('userData'),rendererPath:this.html('library'),
            whenLauncherOperationsIdle:()=>this.whenLauncherOperationsIdle(),historyChanged:()=>this.updateTray(),
            createLibraryWindow:()=>this.createWindow('library',{title:'T-Cube · 常用内容',width:940,height:680,minWidth:800,minHeight:560,backgroundColor:'#f6f8fc',autoHideMenuBar:true,alwaysOnTop:true}),
            role:id=>this.roles.get(id)??null});
        await this.office.start();
        this.whenLauncherOperationsIdle = registerIPC(ipcMain, this.host, sender => this.roles.get(sender.id) ?? null,
            createApplicationCatalog(this.directory, app.getPath('userData')),()=>this.office?.isRestoring??false);
        this.widget.setAlwaysOnTop(true, 'floating');
        await this.widget.loadFile(this.html('widget'));
        this.widget.show();
        const trayImage = nativeImage.createFromPath(path.join(this.directory, 'assets', 'tray.png')).resize({ width: 20, height: 20 });
        this.tray = new Tray(trayImage);
        this.tray.setToolTip('T-Cube'); this.updateTray();
        this.tray.on('click', () => this.toggleWidget());
        this.timer = setTimeout(() => this.tick(), 16);
        void this.host.refreshIcons().catch(error => this.host.reportError(error));
        const refreshDisplays = () => { void this.host.refreshDisplays().catch(error => this.host.reportError(error)); };
        screen.on('display-added', refreshDisplays);
        screen.on('display-removed', refreshDisplays);
        screen.on('display-metrics-changed', refreshDisplays);
        app.on('before-quit', event => {
            if (this.quitting) return;
            event.preventDefault(); this.quitting = true; this.office?.setQuitting(true);
            // A last drag save must finish before windows are destroyed. External launches do not delay quit.
            void (async () => {
                await this.office?.whenIdle(); await this.whenLauncherOperationsIdle(); await this.host.whenIdle({ includeLaunches: false });
                const library = this.office?.libraryWindow;
                if (library && !library.isDestroyed()) {
                    const closed = await new Promise<boolean>(resolve => {
                        const onClosed = () => { this.quitCancelled=null; resolve(true); };
                        this.quitCancelled = () => { library.removeListener('closed',onClosed); this.quitCancelled=null; resolve(false); };
                        library.once('closed',onClosed); library.close();
                    });
                    if (!closed) return;
                }
                app.quit();
            })().catch(error => {
                this.host.reportError(error); app.quit();
            });
        });
        app.on('will-quit', () => this.dispose());
        app.on('activate', () => { this.host.setVisible(true); this.widget.show(); });
        app.on('second-instance', () => this.showSettings());
        if (firstLaunch) this.showSettings();
    }
    private roundFrame(frame: Rect): Rect {
        return { x: Math.round(frame.x), y: Math.round(frame.y), width: Math.round(frame.width), height: Math.round(frame.height) };
    }
    private html(role: WindowRole): string { return path.join(this.directory, 'renderer', `${role}.html`); }
    private createWindow(role: WindowRole, options: BrowserWindowConstructorOptions): BrowserWindow {
        const window = new BrowserWindow({ ...options, show: false, icon: path.join(this.directory, 'assets', 'icon.png'),
            webPreferences: { preload: path.join(this.directory, 'preload.cjs'), sandbox: true, contextIsolation: true,
                nodeIntegration: false, webSecurity: true, allowRunningInsecureContent: false, webviewTag: false } });
        this.roles.set(window.webContents.id, role);
        window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
        window.webContents.on('will-prevent-unload', event => {
            const discard = dialog.showMessageBoxSync(window, {type:'question', title:'尚未保存的内容',
                message:'当前编辑尚未保存，退出并放弃修改？', buttons:['继续编辑','放弃并退出'], defaultId:0, cancelId:0, noLink:true});
            if (discard === 1) event.preventDefault();
            else if (this.quitting) {
                this.quitting = false; this.office?.setQuitting(false);
                this.quitCancelled?.();
                if (this.timer) clearTimeout(this.timer);
                this.timer = setTimeout(() => this.tick(), 16);
            }
        });
        window.webContents.on('will-navigate', event => event.preventDefault());
        window.webContents.on('will-frame-navigate', event => event.preventDefault());
        window.webContents.on('will-attach-webview', event => event.preventDefault());
        window.webContents.session.setPermissionRequestHandler((_contents, _permission, callback) => callback(false));
        window.webContents.session.setPermissionCheckHandler(() => false);
        window.webContents.session.webRequest.onBeforeRequest({ urls: ['http://*/*', 'https://*/*', 'ws://*/*', 'wss://*/*'] },
            (_details, callback) => callback({ cancel: true }));
        window.webContents.on('before-input-event', (_event, input) => {
            if (input.key === 'Escape' && input.type === 'keyDown') this.host?.closeExpanded();
            if (process.platform !== 'win32') this.host?.setFallbackControl(input.control || (input.key === 'Control' && input.type === 'keyDown'));
        });
        const id = window.webContents.id;
        window.on('closed', () => this.roles.delete(id));
        window.on('close', event => {
            if (!this.quitting) {
                event.preventDefault(); window.hide();
                if (role === 'widget') this.host?.setVisible(false);
                if (role === 'expanded') this.host?.closeExpanded();
            }
        });
        return window;
    }
    private broadcast(channel: string, value: unknown): void {
        for (const window of [this.widget, this.settings, this.expanded, this.office?.libraryWindow]) {
            if (window && !window.isDestroyed()) window.webContents.send(channel, value);
        }
    }
    private tick(): void {
        if (this.pollActive || !this.host || this.quitting) return;
        this.pollActive = true;
        try {
            const input = readInputState(), buttons = input.primaryDown || input.secondaryDown;
            if (this.expanded?.isVisible() && buttons && !this.previousButtons) {
                const p = screen.getCursorScreenPoint(), r = this.expanded.getBounds();
                if (p.x < r.x || p.y < r.y || p.x >= r.x + r.width || p.y >= r.y + r.height) this.host.closeExpanded();
            }
            this.previousButtons = buttons;
            const now = Date.now();
            if (now - this.preferenceSample > 1000) { this.reducedMotion = readReducedMotion(); this.preferenceSample = now; }
            this.host.poll((now - this.started) / 1000, this.reducedMotion);
        } catch (error) { this.host.reportError(error); }
        finally {
            this.pollActive = false;
            if (!this.quitting) {
                const state = this.host.snapshot.state;
                const interval = state.interactionActive || state.hovered || this.expanded?.isVisible() ? 16 : state.visible ? 80 : 250;
                this.timer = setTimeout(() => this.tick(), interval);
            }
        }
    }
    showSettings(): void {
        if (!this.settings) {
            this.settings = this.createWindow('settings', { title: 'T-Cube Settings', width: 1020, height: 780, minWidth: 760, minHeight: 580,
                backgroundColor: '#11151d', autoHideMenuBar: true });
            void this.settings.loadFile(this.html('settings')).then(() => { this.settings?.show(); this.settings?.focus(); })
                .catch(error => this.host.reportError(error));
        } else { this.settings.show(); this.settings.focus(); }
        this.host?.closeExpanded();
    }
    private showExpanded(_face: Face): void {
        const frame = this.widget.getBounds(), work = screen.getDisplayMatching(frame).workArea;
        const bounds = { x: Math.round(Math.max(work.x, Math.min(frame.x + frame.width / 2 - 110, work.x + work.width - 220))),
            y: Math.round(Math.max(work.y, Math.min(frame.y + frame.height / 2 - 110, work.y + work.height - 220))), width: 220, height: 220 };
        if (!this.expanded) {
            this.expanded = this.createWindow('expanded', { title: 'T-Cube Expanded', ...bounds, transparent: true, backgroundColor: '#00000000',
                frame: false, resizable: false, skipTaskbar: true, alwaysOnTop: true, hasShadow: false });
            this.expanded.on('blur', () => this.host.closeExpanded());
            void this.expanded.loadFile(this.html('expanded')).then(() => {
                if (this.host.snapshot.state.expandedFace !== null) { this.expanded?.show(); this.expanded?.focus(); }
            }).catch(error => this.host.reportError(error));
        } else { this.expanded.setBounds(bounds); this.expanded.show(); this.expanded.focus(); }
    }
    private toggleWidget(): void {
        const visible = !this.widget.isVisible();
        this.host.setVisible(visible);
    }
    private updateTray(): void {
        const run = (operation: () => unknown) => () => { Promise.resolve().then(operation).catch(error => this.host.reportError(error)); };
        const placements: [string, Placement][] = [['Top left', 'topLeft'], ['Top right', 'topRight'], ['Bottom left', 'bottomLeft'], ['Bottom right', 'bottomRight'], ['Center', 'center']];
        this.tray?.setContextMenu(Menu.buildFromTemplate([
            { label: this.widget.isVisible() ? 'Hide cube' : 'Show cube', click: () => this.toggleWidget() },
            { label: 'Settings…', click: () => this.showSettings() },
            {label:'常用内容…    Ctrl+Shift+Space',click:run(()=>this.office?.showLibrary())},
            {label:`剪贴板历史…（${this.office?.clipboardHistory.state.isEnabled ? '正在记录' : '已暂停'}）`,click:run(()=>this.office?.showClipboardHistory())},
            { label: 'Placement', submenu: placements.map(([label, placement]) => ({ label, click: run(() => this.host.place(placement)) })) },
            { label: 'Cube size', submenu: [0.65, 0.85, 1, 1.25, 1.6].map(scale => ({ label: `${Math.round(scale * 100)}%`,
                click: run(() => this.host.applyConfiguration({ ...this.host.snapshot.state.configuration, scale })) })) },
            { type: 'separator' }, { label: 'Quit T-Cube', click: () => app.quit() }
        ]));
    }
    dispose(): void { this.office?.dispose(); if (this.timer) clearTimeout(this.timer); this.timer = null; this.tray?.destroy(); this.tray = null; }
}
