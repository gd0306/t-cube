import { createHash } from 'node:crypto';
import { win32 } from 'node:path';
import type { InstalledApplication, LauncherItem } from '../shared/contracts';

export interface ApplicationCandidate extends InstalledApplication {
    path: string;
    kind: 'file' | 'shell';
}
export interface ApplicationServices {
    query(): Promise<unknown>;
    validate(path: string): Promise<LauncherItem>;
    shortcut(candidate: ApplicationCandidate): Promise<string>;
    icon(candidate: ApplicationCandidate): Promise<string | null>;
}

export function normalizeApplications(input: unknown): ApplicationCandidate[] {
    if (!Array.isArray(input) || input.length > 5000) throw new Error('无法读取已安装应用列表');
    const apps = new Map<string, ApplicationCandidate>();
    const paths = new Map<string, string>();
    const links = new Map<
        string,
        { identity: string; target: string; arguments: string; appId: string }
    >();
    for (const value of input) {
        if (!value || typeof value !== 'object') continue;
        const { name, path } = value;
        if (
            typeof name !== 'string' ||
            !name.trim() ||
            name.length > 256 ||
            typeof path !== 'string' ||
            path.length > 32767 ||
            /[\0-\x1f]/.test(name + path)
        )
            continue;
        const file =
            /^[a-z]:[\\/]/i.test(path) &&
            !/["<>|?*]/.test(path) &&
            !path.slice(2).includes(':') &&
            /\.(exe|lnk)$/i.test(path);
        const shell = /^[a-z0-9][a-z0-9.!_{}-]{0,511}$/i.test(path);
        if (!file && !shell) continue;
        if (file && /^(?:unins\d*|uninstall(?:er)?|setup)\.exe$/i.test(win32.basename(path)))
            continue;
        const isLink = file && /\.lnk$/i.test(path);
        const linkTarget = typeof value.target === 'string' ? value.target : '';
        if (
            isLink &&
            (!/^[a-z]:[\\/].*\.exe$/i.test(linkTarget) ||
                /[\0-\x1f"<>|?*]/.test(linkTarget) ||
                linkTarget.slice(2).includes(':') ||
                /^(?:unins\d*|uninstall(?:er)?|setup)\.exe$/i.test(win32.basename(linkTarget)))
        )
            continue;
        const target = file ? win32.normalize(path) : path;
        const canonical =
            file &&
            typeof value.canonicalPath === 'string' &&
            /^[a-z]:[\\/]/i.test(value.canonicalPath)
                ? win32.normalize(value.canonicalPath)
                : target;
        const key = file ? canonical.toLowerCase() : `shell:${target}`;
        if (apps.has(key)) continue;
        const id = createHash('sha256').update(key).digest('hex').slice(0, 32);
        if (file) paths.set(id, canonical.toLowerCase());
        if (isLink) {
            const targetKey = win32
                .normalize(
                    typeof value.canonicalTarget === 'string' ? value.canonicalTarget : linkTarget,
                )
                .toLowerCase();
            const argumentsText = typeof value.arguments === 'string' ? value.arguments : '';
            const directory =
                typeof value.canonicalWorkingDirectory === 'string'
                    ? value.canonicalWorkingDirectory
                    : typeof value.workingDirectory === 'string'
                      ? value.workingDirectory
                      : '';
            links.set(id, {
                target: targetKey,
                arguments: argumentsText,
                identity: JSON.stringify([targetKey, argumentsText, directory.toLowerCase()]),
                appId: typeof value.appId === 'string' ? value.appId : '',
            });
        }
        apps.set(key, {
            id,
            name: name.trim(),
            detail: file ? target : 'Windows 应用',
            path: target,
            kind: file ? 'file' : 'shell',
        });
    }
    const preferredLinks = new Map<string, string>(),
        defaultTargets = new Set<string>(),
        appIds = new Set<string>();
    for (const [id, link] of links) {
        if (!preferredLinks.has(link.identity)) preferredLinks.set(link.identity, id);
        if (!link.arguments.trim()) defaultTargets.add(link.target);
        if (link.appId) appIds.add(link.appId);
    }
    return [...apps.values()]
        .filter((entry) => {
            const link = links.get(entry.id);
            if (link) return preferredLinks.get(link.identity) === entry.id;
            if (entry.kind === 'shell') return !appIds.has(entry.path);
            return !defaultTargets.has(paths.get(entry.id)!);
        })
        .sort(
            (a, b) =>
                a.name.localeCompare(b.name, 'zh-CN', { sensitivity: 'base', numeric: true }) ||
                a.id.localeCompare(b.id),
        );
}

export class InstalledApplications {
    private entries = new Map<string, ApplicationCandidate>();
    private loaded = false;
    private validUntil = 0;
    private loading: Promise<InstalledApplication[]> | null = null;
    private images = new Map<string, Promise<string | null>>();
    constructor(private readonly services: ApplicationServices) {}
    async list(refresh = false): Promise<InstalledApplication[]> {
        if (this.loading) return this.loading;
        if (!refresh && this.loaded && Date.now() < this.validUntil) return this.publicEntries();
        this.loading = this.services
            .query()
            .then((raw) => {
                const entries = normalizeApplications(raw);
                this.entries = new Map(entries.map((entry) => [entry.id, entry]));
                this.loaded = true;
                this.validUntil = Date.now() + 60_000;
                this.images.clear();
                return this.publicEntries();
            })
            .finally(() => {
                this.loading = null;
            });
        return this.loading;
    }
    private publicEntries(): InstalledApplication[] {
        return [...this.entries.values()].map(({ id, name, detail }) => ({ id, name, detail }));
    }
    async materialize(id: string): Promise<LauncherItem> {
        if (!this.loaded) await this.list();
        const entry = this.entries.get(id);
        if (!entry) throw new Error('应用列表已更新，请刷新后重新选择');
        const path = entry.kind === 'file' ? entry.path : await this.services.shortcut(entry);
        let item: LauncherItem;
        try {
            item = await this.services.validate(path);
        } catch {
            throw new Error('所选应用已被移动或卸载，请刷新列表后重新选择');
        }
        return { ...item, name: entry.name, kind: 'application' };
    }
    async icons(ids: string[]): Promise<Record<string, string>> {
        if (!Array.isArray(ids) || ids.length > 32) throw new Error('图标请求过多');
        const icons: Record<string, string> = {};
        await Promise.all(
            [...new Set(ids)].map(async (id) => {
                const entry = this.entries.get(id);
                if (!entry) return;
                let image = this.images.get(id);
                if (!image) {
                    image = this.services.icon(entry).catch(() => null);
                    this.images.set(id, image);
                }
                const url = await image;
                if (url) icons[id] = url;
            }),
        );
        return icons;
    }
}
