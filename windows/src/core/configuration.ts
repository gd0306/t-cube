import type { Appearance, Configuration, Face, FaceGroup, LauncherItem, Slots, ThemeId } from '../shared/contracts';
import { FACES } from '../shared/contracts';

export const THEMES: Record<ThemeId, Omit<Appearance, 'glowIntensity'>> = {
    aurora: { primaryHex: '#65DEFF', secondaryHex: '#B793FF', surfaceStyle: 'clear' },
    ocean: { primaryHex: '#4CB8FF', secondaryHex: '#3EE4CF', surfaceStyle: 'clear' },
    sunset: { primaryHex: '#FFAA73', secondaryHex: '#EE79B5', surfaceStyle: 'clear' },
    starfield: { primaryHex: '#8EAAFF', secondaryHex: '#C185FF', surfaceStyle: 'clear' },
    blossom: { primaryHex: '#FF98CE', secondaryHex: '#EAB0FF', surfaceStyle: 'clear' },
    forest: { primaryHex: '#70E5AB', secondaryHex: '#B9E783', surfaceStyle: 'clear' },
    prism: { primaryHex: '#81DFFF', secondaryHex: '#E5B2F8', surfaceStyle: 'iridescent' },
    moonstone: { primaryHex: '#D5E7FF', secondaryHex: '#F3D9EF', surfaceStyle: 'moonstone' },
    auroraFlow: { primaryHex: '#64E4CF', secondaryHex: '#ADA5FF', surfaceStyle: 'aurora' },
};

export function defaultConfiguration(): Configuration {
    const names = ['常用', '开发', '设计', '办公', '文件夹', '更多'];
    return {
        version: 1,
        groups: Object.fromEntries(FACES.map((face, index) => [face, { name: names[index], slots: [null, null, null, null] }])) as Record<Face, FaceGroup>,
        appearance: { ...THEMES.aurora, glowIntensity: 0.55 },
        themeCycle: { isEnabled: false, themes: ['aurora', 'ocean', 'sunset'], intervalSeconds: 10 },
        hover: { isEnabled: true, multiplier: 4 },
        expandsFacesOnClick: true, autoRotatesWhenIdle: true, scale: 1, windowPosition: null,
    };
}

function object(value: unknown, label: string): Record<string, unknown> {
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error(`Invalid ${label}`);
    return value as Record<string, unknown>;
}
function boolean(value: unknown, label: string): boolean {
    if (typeof value !== 'boolean') throw new Error(`Invalid ${label}`);
    return value;
}
function number(value: unknown, min: number, max: number, label: string): number {
    if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max) throw new Error(`Invalid ${label}`);
    return value;
}
function name(value: unknown): string {
    if (typeof value !== 'string' || !value.trim()) throw new Error('Invalid name');
    return value.trim();
}
// Lexical Windows keys keep drive/UNC roots intact without a node:path dependency.
function targetKey(path: string): string {
    // This exact namespace prefix disables Win32 separator/dot expansion. Its
    // components must not be merged with ordinary paths by lexical guessing.
    if (path.startsWith('\\\\?\\')) return path.toLowerCase();
    const normalized = path.replaceAll('/', '\\');
    const drive = /^([a-z]:)\\+/i.exec(normalized);
    const unc = /^\\\\([^\\]+)\\+([^\\]+)(?:\\+|$)/.exec(normalized);
    const root = drive ? `${drive[1]}\\` : unc ? `\\\\${unc[1]}\\${unc[2]}\\` : '';
    const rootLength = drive?.[0].length ?? unc?.[0].length ?? 0;
    const parts: string[] = [];
    for (const component of normalized.slice(rootLength).split('\\')) {
        if (component === '.' || !component) continue;
        if (component === '..') parts.pop();
        else parts.push(component);
    }
    return (root + parts.join('\\')).toLowerCase();
}
function launcherItem(value: unknown): LauncherItem {
    const item = object(value, 'item');
    if (typeof item.id !== 'string' || !item.id.trim() || typeof item.path !== 'string'
        || !/^(?:[a-z]:[\\/]|\\\\[^\\/]+[\\/][^\\/]+)/i.test(item.path)
        || item.path.includes('\0') || !['application', 'folder'].includes(item.kind as string)) throw new Error('Invalid item');
    return { id: item.id, path: item.path, name: name(item.name), kind: item.kind as LauncherItem['kind'] };
}

/** Missing newer fields receive native defaults; malformed present data fails closed. */
export function normalizeConfiguration(input: unknown): Configuration {
    const source = object(input, 'configuration'), defaults = defaultConfiguration();
    if (source.version !== 1) throw new Error('Unsupported configuration version');
    const sourceGroups = object(source.groups, 'groups');
    if (Object.keys(sourceGroups).length !== 6 || FACES.some(face => !(face in sourceGroups))) throw new Error('Invalid groups');
    const groups = {} as Record<Face, FaceGroup>;
    for (const face of FACES) {
        const group = object(sourceGroups[face], 'group');
        if (!Array.isArray(group.slots) || group.slots.length !== 4) throw new Error('Invalid slot count');
        const slots = Array.from(group.slots, item => item === null ? null : launcherItem(item)) as Slots;
        const items = slots.filter((item): item is LauncherItem => item !== null);
        if (new Set(items.map(item => item.id)).size !== items.length || new Set(items.map(item => targetKey(item.path))).size !== items.length) throw new Error('Duplicate item');
        groups[face] = { name: name(group.name), slots };
    }
    const rawAppearance = source.appearance === undefined ? defaults.appearance : object(source.appearance, 'appearance');
    if (![rawAppearance.primaryHex, rawAppearance.secondaryHex].every(value => typeof value === 'string' && /^#[\da-f]{6}$/i.test(value))) throw new Error('Invalid appearance');
    const surfaceStyle = rawAppearance.surfaceStyle === undefined ? 'clear' : rawAppearance.surfaceStyle;
    if (!['clear', 'iridescent', 'moonstone', 'aurora'].includes(surfaceStyle as string)) throw new Error('Invalid appearance');
    const appearance: Appearance = { primaryHex: rawAppearance.primaryHex as string, secondaryHex: rawAppearance.secondaryHex as string,
        glowIntensity: number(rawAppearance.glowIntensity, 0, 1, 'appearance'), surfaceStyle: surfaceStyle as Appearance['surfaceStyle'] };
    const cycle = source.themeCycle === undefined ? defaults.themeCycle : object(source.themeCycle, 'theme cycle');
    const enabled = boolean(cycle.isEnabled, 'theme cycle');
    if (!Array.isArray(cycle.themes) || cycle.themes.some(t => typeof t !== 'string' || !Object.hasOwn(THEMES, t))
        || new Set(cycle.themes).size !== cycle.themes.length || (enabled && cycle.themes.length < 2) || ![10, 20].includes(cycle.intervalSeconds as number)) throw new Error('Invalid theme cycle');
    const hover = source.hover === undefined ? defaults.hover : object(source.hover, 'hover');
    const position = source.windowPosition === undefined || source.windowPosition === null ? null : object(source.windowPosition, 'position');
    return {
        version: 1, groups, appearance,
        themeCycle: { isEnabled: enabled, themes: [...cycle.themes] as ThemeId[], intervalSeconds: cycle.intervalSeconds as 10 | 20 },
        hover: { isEnabled: boolean(hover.isEnabled, 'hover'), multiplier: number(hover.multiplier, 1.1, 4, 'hover') },
        expandsFacesOnClick: source.expandsFacesOnClick === undefined ? true : boolean(source.expandsFacesOnClick, 'face expansion'),
        autoRotatesWhenIdle: source.autoRotatesWhenIdle === undefined ? true : boolean(source.autoRotatesWhenIdle, 'idle rotation'),
        scale: number(source.scale, 0.65, 1.6, 'scale'),
        windowPosition: position ? { x: number(position.x, -Infinity, Infinity, 'position'), y: number(position.y, -Infinity, Infinity, 'position') } : null,
    };
}

export function resolveAppearance(config: Configuration, elapsedSeconds: number): { appearance: Appearance; theme: ThemeId | null } {
    if (!config.themeCycle.isEnabled) return { appearance: { ...config.appearance }, theme: null };
    const elapsed = Number.isFinite(elapsedSeconds) ? Math.max(0, elapsedSeconds) : 0;
    const theme = config.themeCycle.themes[Math.floor(elapsed / config.themeCycle.intervalSeconds) % config.themeCycle.themes.length];
    return { appearance: { ...THEMES[theme], glowIntensity: config.appearance.glowIntensity }, theme };
}

function slotIndex(slot: number): void {
    if (!Number.isInteger(slot) || slot < 0 || slot > 3) throw new Error('Invalid slot');
}
export function addTarget(config: Configuration, face: Face, item: LauncherItem, slot?: number, replacing = false): Configuration {
    const next = normalizeConfiguration(config), group = next.groups[face];
    const destination = slot ?? group.slots.indexOf(null);
    if (destination === -1) throw new Error('Group full');
    slotIndex(destination);
    if (!replacing && group.slots[destination] !== null) throw new Error('Occupied slot');
    group.slots[destination] = item;
    return normalizeConfiguration(next);
}
export function removeTarget(config: Configuration, face: Face, slot: number): Configuration {
    slotIndex(slot); const next = normalizeConfiguration(config);
    if (!next.groups[face].slots[slot]) throw new Error('Empty slot');
    next.groups[face].slots[slot] = null; return next;
}
export function moveTarget(config: Configuration, face: Face, source: number, destination: number): Configuration {
    slotIndex(source); slotIndex(destination); const next = normalizeConfiguration(config);
    const slots = next.groups[face].slots;
    if (!slots[source]) throw new Error('Empty slot');
    const [item] = slots.splice(source, 1); slots.splice(destination, 0, item); return next;
}
export function renameGroup(config: Configuration, face: Face, value: string): Configuration {
    const next = normalizeConfiguration(config); next.groups[face].name = name(value); return next;
}
