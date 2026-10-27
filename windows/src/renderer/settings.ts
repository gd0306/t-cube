import { THEMES } from '../core/configuration';
import {
    FACES,
    type Configuration,
    type Face,
    type Placement,
    type Snapshot,
    type ThemeId,
} from '../shared/contracts';
import { subscribe } from './util';
import { NameDraft, PreferenceQueue, shouldDeferSettingsRender } from './state';
import { ApplicationPicker } from './application-picker';
const applicationPicker = new ApplicationPicker();
const content = document.querySelector<HTMLElement>('#content')!,
    error = document.querySelector<HTMLElement>('#error')!;
let snapshot: Snapshot | undefined,
    face: Face = 'front',
    page = 'groups';
let preferences: PreferenceQueue | undefined;
let contentPointerActive = false;
const nameDraft = new NameDraft();
const labels: Record<ThemeId, string> = {
    aurora: '极光',
    ocean: '海洋',
    sunset: '日落',
    starfield: '星空',
    blossom: '花漾',
    forest: '森林',
    prism: '棱镜',
    moonstone: '月光石',
    auroraFlow: '流光极光',
};
function run(action: Promise<void>) {
    error.textContent = '';
    void action.catch((reason) => {
        error.textContent = reason instanceof Error ? reason.message : String(reason);
    });
}
window.tcube.onError((message) => {
    error.textContent = message;
});
function element<K extends keyof HTMLElementTagNameMap>(
    tag: K,
    text?: string,
    className?: string,
): HTMLElementTagNameMap[K] {
    const el = document.createElement(tag);
    if (text !== undefined) el.textContent = text;
    if (className) el.className = className;
    return el;
}
function button(text: string, action: () => void, className?: string) {
    const el = element('button', text, className);
    el.type = 'button';
    el.onclick = action;
    return el;
}
function heading(title: string, description: string) {
    content.append(element('h2', title), element('p', description));
}
function save(edit: (config: Configuration) => void) {
    if (!preferences) return;
    run(preferences.edit(edit));
}
function row(title: string, control: HTMLElement, extra?: HTMLElement) {
    const wrap = element('div', undefined, 'row'),
        label = element('label', title);
    if ('id' in control) {
        control.id ||= `control-${Math.random().toString(36).slice(2)}`;
        label.htmlFor = control.id;
    }
    wrap.append(label, control);
    if (extra) wrap.append(extra);
    content.append(wrap);
}
function checkbox(value: boolean, change: (value: boolean) => void) {
    const el = element('input');
    el.type = 'checkbox';
    el.checked = value;
    el.onchange = () => change(el.checked);
    return el;
}
function range(
    value: number,
    min: number,
    max: number,
    step: number,
    change: (value: number) => void,
    format: (value: number) => string,
) {
    const el = element('input');
    el.type = 'range';
    el.min = String(min);
    el.max = String(max);
    el.step = String(step);
    el.value = String(value);
    const out = element('output', format(value));
    el.oninput = () => {
        out.textContent = format(Number(el.value));
    };
    el.onchange = () => change(Number(el.value));
    return [el, out] as const;
}
function renderGroups(data: Snapshot) {
    heading('应用分组', '为立方体的六个面分别安排应用或文件夹。');
    const tabs = element('div', undefined, 'tabs');
    FACES.forEach((f) => {
        const b = button(
            data.state.configuration.groups[f].name,
            () => {
                face = f;
                render();
            },
            f === face ? 'active' : '',
        );
        b.setAttribute('aria-pressed', String(f === face));
        tabs.append(b);
    });
    content.append(tabs);
    const group = data.state.configuration.groups[face],
        nameRow = element('div', undefined, 'name'),
        label = element('label', '分组名称'),
        input = element('input');
    input.type = 'text';
    input.value = nameDraft.value(face, group.name);
    input.id = 'group-name';
    label.htmlFor = input.id;
    const editingFace = face;
    input.oninput = () => nameDraft.change(editingFace, input.value);
    input.onchange = () => {
        const name = input.value;
        nameDraft.commit(editingFace, name);
        error.textContent = '';
        void window.tcube.renameGroup({ face: editingFace, name }).catch((reason) => {
            nameDraft.clear(editingFace);
            error.textContent = reason instanceof Error ? reason.message : String(reason);
            render();
        });
    };
    input.onblur = () => {
        if (!contentPointerActive) setTimeout(render, 0);
    };
    nameRow.append(label, input);
    content.append(nameRow);
    const slots = element('div', undefined, 'slots');
    group.slots.forEach((item, slot) => {
        const line = element('div', undefined, 'slot');
        line.append(element('span', String(slot + 1).padStart(2, '0'), 'number'));
        if (item && data.icons[item.id]) {
            const img = element('img');
            img.src = data.icons[item.id];
            img.alt = '';
            line.append(img);
        }
        line.append(element('span', item?.name ?? '空位置', item ? 'item' : 'item empty'));
        for (const [kind, title] of [
            ['application', '添加应用'],
            ['folder', '选择文件夹'],
        ] as const)
            line.append(button(title, () => {
                if (kind === 'application') applicationPicker.open(face, slot);
                else run(window.tcube.chooseTarget({ face, slot, kind }));
            }));
        if (item) {
            const up = button('↑', () =>
                run(window.tcube.moveTarget({ face, source: slot, destination: slot - 1 })),
            );
            up.disabled = slot === 0;
            up.setAttribute('aria-label', `上移 ${item.name}`);
            const down = button('↓', () =>
                run(window.tcube.moveTarget({ face, source: slot, destination: slot + 1 })),
            );
            down.disabled = slot === 3;
            down.setAttribute('aria-label', `下移 ${item.name}`);
            line.append(
                up,
                down,
                button('移除', () => run(window.tcube.removeTarget({ face, slot }))),
            );
        }
        line.ondragover = (event) => {
            event.preventDefault();
        };
        line.ondrop = (event) => {
            event.preventDefault();
            const files = Array.from(event.dataTransfer?.files ?? []);
            if (files.length)
                run(
                    window.tcube.dropTargets({
                        paths: window.tcube.getDroppedPaths(files),
                        face,
                        slot,
                    }),
                );
        };
        slots.append(line);
    });
    content.append(slots, element('p', '也可以将应用或文件夹拖放到位置中。'));
}
function renderAppearance(data: Snapshot) {
    const config = data.state.configuration;
    heading('外观与主题', '选择色彩，或创建自己的玻璃外观。');
    content.append(element('h3', '主题预设'));
    const themes = element('div', undefined, 'themes');
    for (const id of Object.keys(THEMES) as ThemeId[]) {
        const b = button(
            labels[id],
            () =>
                save((c) => {
                    c.appearance = { ...THEMES[id], glowIntensity: c.appearance.glowIntensity };
                }),
            JSON.stringify(THEMES[id]) ===
                JSON.stringify({
                    primaryHex: config.appearance.primaryHex,
                    secondaryHex: config.appearance.secondaryHex,
                    surfaceStyle: config.appearance.surfaceStyle,
                })
                ? 'active'
                : '',
        );
        const swatch = element('span', undefined, 'swatch');
        swatch.style.background = `linear-gradient(135deg, ${THEMES[id].primaryHex}, ${THEMES[id].secondaryHex})`;
        b.prepend(swatch);
        themes.append(b);
    }
    content.append(themes);
    for (const [key, title] of [
        ['primaryHex', '主色'],
        ['secondaryHex', '辅助色'],
    ] as const) {
        const color = element('input');
        color.type = 'color';
        color.value = config.appearance[key];
        color.onchange = () =>
            save((c) => {
                c.appearance[key] = color.value;
            });
        row(title, color);
    }
    const [glow, glowOut] = range(
        config.appearance.glowIntensity,
        0,
        1,
        0.05,
        (v) =>
            save((c) => {
                c.appearance.glowIntensity = v;
            }),
        (v) => `${Math.round(v * 100)}%`,
    );
    row('光晕强度', glow, glowOut);
    const style = element('select');
    for (const [value, title] of [
        ['clear', '通透'],
        ['iridescent', '虹彩'],
        ['moonstone', '月光石'],
        ['aurora', '极光'],
    ]) {
        const option = element('option', title);
        option.value = value;
        style.append(option);
    }
    style.value = config.appearance.surfaceStyle;
    style.onchange = () =>
        save((c) => {
            c.appearance.surfaceStyle = style.value as Configuration['appearance']['surfaceStyle'];
        });
    row('表面效果', style);
    content.append(element('h3', '主题轮换'));
    row(
        '启用轮换',
        checkbox(config.themeCycle.isEnabled, (value) => {
            if (value && config.themeCycle.themes.length < 2) {
                error.textContent = '请至少选择两个主题。';
                render();
                return;
            }
            save((c) => {
                c.themeCycle.isEnabled = value;
            });
        }),
    );
    const checks = element('div', undefined, 'checks');
    for (const id of Object.keys(THEMES) as ThemeId[]) {
        const label = element('label'),
            input = checkbox(config.themeCycle.themes.includes(id), (checked) => {
                const current = preferences?.draft ?? config;
                const selected = checked
                    ? [...current.themeCycle.themes, id]
                    : current.themeCycle.themes.filter((t) => t !== id);
                if (current.themeCycle.isEnabled && selected.length < 2) {
                    error.textContent = '轮换至少需要两个主题。';
                    render();
                    return;
                }
                save((c) => {
                    c.themeCycle.themes = selected;
                });
            });
        label.append(input, document.createTextNode(` ${labels[id]}`));
        checks.append(label);
    }
    content.append(checks);
    const interval = element('select');
    for (const seconds of [10, 20]) {
        const option = element('option', `${seconds} 秒`);
        option.value = String(seconds);
        interval.append(option);
    }
    interval.value = String(config.themeCycle.intervalSeconds);
    interval.onchange = () =>
        save((c) => {
            c.themeCycle.intervalSeconds = Number(interval.value) as 10 | 20;
        });
    row('轮换间隔', interval);
}
function renderBehavior(data: Snapshot) {
    const config = data.state.configuration;
    heading('交互与位置', '调整立方体的大小和桌面行为。');
    row(
        '悬停放大',
        checkbox(config.hover.isEnabled, (v) =>
            save((c) => {
                c.hover.isEnabled = v;
            }),
        ),
    );
    const [hover, out] = range(
        config.hover.multiplier,
        1.1,
        4,
        0.1,
        (v) =>
            save((c) => {
                c.hover.multiplier = v;
            }),
        (v) => `${v.toFixed(1)}×`,
    );
    row('放大倍数', hover, out);
    const [scale, scaleOut] = range(
        config.scale,
        0.65,
        1.6,
        0.05,
        (v) =>
            save((c) => {
                c.scale = v;
            }),
        (v) => `${Math.round(v * 100)}%`,
    );
    row('默认大小', scale, scaleOut);
    row(
        '空闲时旋转',
        checkbox(config.autoRotatesWhenIdle, (v) =>
            save((c) => {
                c.autoRotatesWhenIdle = v;
            }),
        ),
    );
    row(
        '点击展开面',
        checkbox(config.expandsFacesOnClick, (v) =>
            save((c) => {
                c.expandsFacesOnClick = v;
            }),
        ),
    );
    content.append(element('h3', '快速放置'));
    const placements = element('div', undefined, 'placements');
    for (const [id, title] of [
        ['topLeft', '左上'],
        ['topRight', '右上'],
        ['center', '居中'],
        ['bottomLeft', '左下'],
        ['bottomRight', '右下'],
    ] as [Placement, string][])
        placements.append(button(title, () => run(window.tcube.place(id))));
    content.append(placements);
}
function render() {
    if (!snapshot) return;
    if (contentPointerActive || shouldDeferSettingsRender(page, document.activeElement?.id ?? null))
        return;
    const data = {
        ...snapshot,
        state: {
            ...snapshot.state,
            configuration: preferences?.draft ?? snapshot.state.configuration,
        },
    };
    content.replaceChildren();
    if (page === 'groups') renderGroups(data);
    else if (page === 'appearance') renderAppearance(data);
    else renderBehavior(data);
}
document.querySelectorAll<HTMLButtonElement>('nav button').forEach((b) => {
    b.onclick = () => {
        page = b.dataset.page!;
        document
            .querySelectorAll('nav button')
            .forEach((el) => el.classList.toggle('active', el === b));
        render();
    };
});
document.querySelector<HTMLButtonElement>('#quit')!.onclick = () => run(window.tcube.quit());
let renderedKey = '';
subscribe((data) => {
    snapshot = data;
    if (!preferences) {
        preferences = new PreferenceQueue(
            data.state.configuration,
            (config) => window.tcube.applyConfiguration(config),
            async () => (await window.tcube.getSnapshot()).state.configuration,
            render,
        );
    } else preferences.update(data.state.configuration);
    for (const groupFace of FACES)
        nameDraft.observe(groupFace, data.state.configuration.groups[groupFace].name);
    const key = JSON.stringify([data.state.configuration, data.icons]);
    if (key !== renderedKey) {
        renderedKey = key;
        render();
    }
});

content.addEventListener(
    'pointerdown',
    () => {
        contentPointerActive = true;
    },
    true,
);
function finishContentPointer() {
    if (!contentPointerActive) return;
    setTimeout(() => {
        contentPointerActive = false;
        render();
    }, 0);
}
window.addEventListener('pointerup', finishContentPointer, true);
window.addEventListener('pointercancel', finishContentPointer, true);
window.addEventListener('blur', finishContentPointer);
