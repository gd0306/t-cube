import { readFile } from 'node:fs/promises';
import { atomicWriteJSON } from '../core/atomic-json';

export interface LoginItemAdapter {
    get(): { registered: boolean; enabled: boolean; blocked: boolean };
    set(enabled: boolean): void;
}
export interface LoginPreference { read(): Promise<boolean | null>; write(enabled: boolean): Promise<void> }
/** Kept separate from update preferences so either update mode preserves an explicit opt-out. */
export class LoginPreferenceStore implements LoginPreference {
    private loaded: Promise<boolean | null> | undefined;
    constructor(private readonly file: string) {}
    read(): Promise<boolean | null> {
        this.loaded ??= readFile(this.file, 'utf8').then(text => {
            const value = JSON.parse(text);
            if (value.version !== 1 || typeof value.enabled !== 'boolean') throw Error('Invalid login preferences');
            return value.enabled as boolean;
        }).catch(error => { if (error.code === 'ENOENT') return null; throw error; });
        return this.loaded;
    }
    async write(enabled: boolean): Promise<void> { await this.read(); await atomicWriteJSON(this.file, { version: 1, enabled }); this.loaded = Promise.resolve(enabled); }
}
/** Applies the first-run default once. Later launches only read the actual OS state. */
export class LoginStartupController {
    private started: Promise<void> | undefined;
    private mutations = Promise.resolve();
    private failure = '';
    private unreadable = false;
    constructor(private readonly adapter: LoginItemAdapter, private readonly store: LoginPreference) {}
    get enabled(): boolean { try { return this.adapter.get().enabled; } catch (error) { this.report(error); return false; } }
    get status(): string { return this.failure; }
    private report(error: unknown): void { this.failure = `登录启动设置失败：${error instanceof Error ? error.message : String(error)}`; }
    start(): Promise<void> {
        this.started ??= (async () => {
            let preference: boolean | null;
            try { preference = await this.store.read(); } catch (error) { this.unreadable = true; this.report(error); return; }
            if (preference !== null) return;
            try {
                const state = this.adapter.get();
                // Persist initialization before registration, including failures, so OS choices are never overwritten on restart.
                await this.store.write(!state.blocked);
                if (state.blocked) { this.report(Error('系统已禁止登录启动，请在 Windows 启动应用设置中查看。')); return; }
                if (!state.registered) this.adapter.set(true);
                if (!this.adapter.get().enabled) throw Error('系统未启用登录启动，请在 Windows 启动应用设置中查看。');
            } catch (error) { this.report(error); }
        })();
        return this.started;
    }
    setEnabled(enabled: boolean): Promise<void> {
        if (typeof enabled !== 'boolean') return Promise.reject(Error('Invalid login preference'));
        const operation = this.mutations.then(async () => {
            await this.start();
            try {
                if (this.unreadable) throw Error('登录启动设置不可读取，原文件已保留。');
                if (enabled && this.adapter.get().blocked) throw Error('系统已禁止登录启动，请在 Windows 启动应用设置中查看。');
                await this.store.write(enabled);
                this.adapter.set(enabled);
                if (this.adapter.get().enabled !== enabled) throw Error('系统未接受登录启动设置，请在 Windows 启动应用设置中查看。');
                this.failure = '';
            } catch (error) { this.report(error); throw error; }
        });
        this.mutations = operation.catch(() => {}); return operation;
    }
}
