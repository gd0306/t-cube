import type { Point, Rect, Size } from '../shared/contracts';

/** Descriptors are primary-first; IDs remain stable when work areas change. */
export interface DisplayDescriptor { id: string; workArea: Rect }
export interface DisplayPositionMemory { version: 1; activeDisplayId: string | null; positions: Record<string, Point> }
export const emptyDisplayPositionMemory = (): DisplayPositionMemory => ({ version: 1, activeDisplayId: null, positions: {} });
export function normalizeDisplayPositionMemory(input: unknown): DisplayPositionMemory {
    if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Invalid display positions');
    const source = input as Record<string, unknown>;
    if (source.version !== 1 || !(source.activeDisplayId === null || (typeof source.activeDisplayId === 'string' && source.activeDisplayId.length > 0 && source.activeDisplayId.length <= 256))
        || !source.positions || typeof source.positions !== 'object' || Array.isArray(source.positions)) throw new Error('Invalid display positions');
    const entries = Object.entries(source.positions);
    if (entries.length > 128) throw new Error('Too many display positions');
    const positions: Record<string, Point> = {};
    for (const [id, value] of entries) {
        if (!id || id.length > 256 || !value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid display position');
        const { x, y } = value as Point;
        if (![x, y].every(number => typeof number === 'number' && Number.isFinite(number) && number >= 0 && number <= 1)) throw new Error('Invalid display position');
        Object.defineProperty(positions, id, { value: { x, y }, enumerable: true, configurable: true, writable: true });
    }
    return { version: 1, activeDisplayId: source.activeDisplayId as string | null, positions };
}
export function nearestDisplay(frame: Rect, displays: DisplayDescriptor[]): DisplayDescriptor | undefined {
    const x = frame.x + frame.width / 2, y = frame.y + frame.height / 2;
    const distance = ({ workArea: a }: DisplayDescriptor) => (x - Math.max(a.x, Math.min(x, a.x + a.width))) ** 2 + (y - Math.max(a.y, Math.min(y, a.y + a.height))) ** 2;
    return displays.reduce<DisplayDescriptor | undefined>((best, display) => !best || distance(display) < distance(best) ? display : best, undefined);
}
export function rememberDisplayPosition(memory: DisplayPositionMemory, frame: Rect, displays: DisplayDescriptor[]): DisplayPositionMemory {
    const next = normalizeDisplayPositionMemory(memory), display = nearestDisplay(frame, displays);
    if (!display) return next;
    const area = display.workArea;
    const normalized = (value: number, available: number) => available > 0 ? Math.max(0, Math.min(1, value / available)) : 0;
    next.activeDisplayId = display.id;
    Object.defineProperty(next.positions, display.id, { value: { x: normalized(frame.x - area.x, area.width - frame.width), y: normalized(frame.y - area.y, area.height - frame.height) }, enumerable: true, configurable: true, writable: true });
    return next;
}
export function restoreDisplayPosition(memory: DisplayPositionMemory, size: Size, displays: DisplayDescriptor[], fallback: Point): Point {
    const display = displays.find(display => display.id === memory.activeDisplayId) ?? displays[0];
    if (!display) return { ...fallback };
    const area = display.workArea, normalized = Object.hasOwn(memory.positions, display.id) ? memory.positions[display.id] : undefined;
    const width = Math.max(0, area.width - size.width), height = Math.max(0, area.height - size.height);
    return normalized ? { x: area.x + width * normalized.x, y: area.y + height * normalized.y }
        : { x: area.x + Math.max(0, Math.min(width, fallback.x - area.x)), y: area.y + Math.max(0, Math.min(height, fallback.y - area.y)) };
}
