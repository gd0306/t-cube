import type { Face, InstalledApplication } from '../shared/contracts';

/** Lives outside #content so background settings updates cannot destroy an open picker. */
export class ApplicationPicker {
    private dialog = document.createElement('dialog');
    private search = document.createElement('input');
    private list = document.createElement('div');
    private status = document.createElement('p');
    private refresh = document.createElement('button');
    private browse = document.createElement('button');
    private entries: InstalledApplication[] = [];
    private images = new Map<string, string>();
    private observer: IntersectionObserver | null = null;
    private pendingIcons = new Set<string>();
    private iconTimer = 0;
    private loadingIcons = false;
    private generation = 0;
    private destination: { face: Face; slot: number } | null = null;
    private adding = false;
    private loading = false;

    constructor() {
        this.dialog.className = 'application-picker';
        this.dialog.setAttribute('aria-labelledby', 'application-picker-title');
        const heading = document.createElement('h2');
        heading.id = 'application-picker-title';
        heading.textContent = '添加应用';
        const description = document.createElement('p');
        description.textContent = '选择已安装的应用，加入当前快捷位置。';
        this.search.type = 'search';
        this.search.placeholder = '搜索已安装的应用';
        this.search.setAttribute('aria-label', '搜索已安装的应用');
        this.search.oninput = () => this.render();
        this.list.className = 'application-results';
        this.list.setAttribute('aria-label', '已安装的应用');
        this.status.className = 'application-status';
        this.status.setAttribute('role', 'status');
        this.refresh.type = 'button';
        this.refresh.textContent = '刷新列表';
        this.refresh.onclick = () => {
            void this.load(true);
        };
        this.browse.type = 'button';
        this.browse.textContent = '浏览文件…';
        this.browse.onclick = () => {
            void this.browseFile();
        };
        const cancel = document.createElement('button');
        cancel.type = 'button';
        cancel.textContent = '取消';
        cancel.onclick = () => this.dialog.close();
        const actions = document.createElement('footer');
        actions.append(this.refresh, this.browse, cancel);
        this.dialog.append(heading, description, this.search, this.status, this.list, actions);
        this.dialog.addEventListener('close', () => {
            this.generation++;
            this.destination = null;
            this.observer?.disconnect();
            this.pendingIcons.clear();
            clearTimeout(this.iconTimer);
            this.iconTimer = 0;
        });
        document.body.append(this.dialog);
    }

    open(face: Face, slot: number): void {
        if (this.dialog.open) return;
        this.destination = { face, slot };
        this.adding = false;
        this.search.disabled = false;
        this.search.value = '';
        this.entries = [];
        this.images.clear();
        this.dialog.showModal();
        this.search.focus();
        void this.load();
    }
    private async load(refresh = false): Promise<void> {
        if (this.adding) return;
        const generation = ++this.generation;
        this.loading = true;
        this.refresh.disabled = true;
        this.status.textContent = '正在读取已安装应用…';
        try {
            const entries = await window.tcube.listInstalledApplications(refresh);
            if (generation !== this.generation || !this.dialog.open) return;
            this.loading = false;
            this.entries = entries;
            this.images.clear();
            this.render();
        } catch (reason) {
            if (generation === this.generation && this.dialog.open) {
                this.loading = false;
                this.status.textContent = `${this.message(reason)}。可使用“浏览文件”添加应用。`;
            }
        } finally {
            if (generation === this.generation) this.refresh.disabled = this.adding;
        }
    }
    private render(): void {
        this.refresh.disabled = this.adding;
        this.browse.disabled = this.adding;
        this.search.disabled = this.adding;
        this.observer?.disconnect();
        this.pendingIcons.clear();
        this.list.replaceChildren();
        const term = this.search.value.trim().toLocaleLowerCase();
        const matches = this.entries.filter((entry) =>
            entry.name.toLocaleLowerCase().includes(term),
        );
        this.status.textContent = this.loading
            ? '正在读取已安装应用…'
            : matches.length
              ? `${matches.length} 个应用`
              : term
                ? '没有找到匹配应用，可尝试其他名称。'
                : '未找到已登记的应用，可浏览文件添加。';
        this.observer = new IntersectionObserver(
            (entries) => {
                for (const entry of entries) {
                    if (!entry.isIntersecting) continue;
                    const id = (entry.target as HTMLElement).dataset.applicationId!;
                    if (!this.images.has(id)) this.pendingIcons.add(id);
                    this.observer?.unobserve(entry.target);
                }
                if (this.pendingIcons.size && !this.iconTimer)
                    this.iconTimer = window.setTimeout(() => {
                        this.iconTimer = 0;
                        void this.loadIcons();
                    }, 0);
            },
            { root: this.list, rootMargin: '80px' },
        );
        for (const entry of matches) {
            const row = document.createElement('button');
            row.type = 'button';
            row.className = 'application-result';
            row.dataset.applicationId = entry.id;
            row.disabled = this.adding;
            const picture = document.createElement('span');
            picture.className = 'application-icon';
            if (this.images.get(entry.id)) this.paintIcon(picture, this.images.get(entry.id)!);
            const text = document.createElement('span'),
                name = document.createElement('strong'),
                detail = document.createElement('small');
            name.textContent = entry.name;
            detail.textContent = entry.detail;
            text.append(name, detail);
            row.append(picture, text);
            row.onclick = () => {
                void this.select(entry);
            };
            this.list.append(row);
            this.observer.observe(row);
        }
    }
    private paintIcon(container: Element, url: string): void {
        const img = document.createElement('img');
        img.alt = '';
        img.src = url;
        container.replaceChildren(img);
    }
    private async loadIcons(): Promise<void> {
        if (this.loadingIcons) return;
        this.loadingIcons = true;
        const generation = this.generation;
        const ids = [...this.pendingIcons].slice(0, 16);
        ids.forEach((id) => this.pendingIcons.delete(id));
        try {
            const icons = await window.tcube.installedApplicationIcons(ids);
            if (generation !== this.generation || !this.dialog.open) return;
            for (const id of ids) {
                this.images.set(id, icons[id] ?? '');
                const row = this.list.querySelector(
                    `[data-application-id="${id}"] .application-icon`,
                );
                if (row && icons[id]) this.paintIcon(row, icons[id]);
            }
        } catch {
            /* The list and selection remain usable without icons. */
        } finally {
            this.loadingIcons = false;
            if (this.pendingIcons.size && this.dialog.open && !this.iconTimer) {
                this.iconTimer = window.setTimeout(() => {
                    this.iconTimer = 0;
                    void this.loadIcons();
                }, 0);
            }
        }
    }
    private async select(entry: InstalledApplication): Promise<void> {
        if (this.adding || !this.destination) return;
        const generation = this.generation,
            destination = this.destination;
        this.adding = true;
        this.render();
        this.status.textContent = `正在添加 ${entry.name}…`;
        try {
            await window.tcube.addInstalledApplication({ ...destination, applicationId: entry.id });
            if (generation === this.generation) this.dialog.close();
        } catch (reason) {
            if (generation === this.generation) {
                this.adding = false;
                this.render();
                this.status.textContent = this.message(reason);
            }
        }
    }
    private async browseFile(): Promise<void> {
        if (this.adding || !this.destination) return;
        const generation = this.generation;
        this.adding = true;
        try {
            await window.tcube.chooseTarget({ ...this.destination, kind: 'application' });
            if (generation === this.generation) this.dialog.close();
        } catch (reason) {
            if (generation === this.generation) this.status.textContent = this.message(reason);
        } finally {
            if (generation === this.generation) this.adding = false;
        }
    }
    private message(reason: unknown): string {
        return (reason instanceof Error ? reason.message : String(reason)).replace(
            /^Error invoking remote method '[^']+': Error: /,
            '',
        );
    }
}
