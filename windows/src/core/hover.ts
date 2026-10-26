import type { HoverGeometryContract, HoverSettings, Placement, Point, Rect, Size } from '../shared/contracts';

function contains(frame: Rect, point: Point): boolean {
    return point.x >= frame.x && point.x < frame.x + frame.width && point.y >= frame.y && point.y < frame.y + frame.height;
}
function nearestScreen(frame: Rect, screens: Rect[]): Rect | undefined {
    const x = frame.x + frame.width / 2, y = frame.y + frame.height / 2;
    const distance = (screen: Rect) => (x - Math.max(screen.x, Math.min(x, screen.x + screen.width))) ** 2
        + (y - Math.max(screen.y, Math.min(y, screen.y + screen.height))) ** 2;
    return screens.reduce<Rect | undefined>((best, screen) => !best || distance(screen) < distance(best) ? screen : best, undefined);
}
function clamp(frame: Rect, screens: Rect[]): Rect {
    const screen = nearestScreen(frame, screens);
    if (!screen) return { ...frame };
    return { ...frame, x: Math.max(screen.x, Math.min(frame.x, screen.x + screen.width - frame.width)),
        y: Math.max(screen.y, Math.min(frame.y, screen.y + screen.height - frame.height)) };
}

/** DIP geometry with Windows top-left screen coordinates. Hover never persists a temporary frame. */
export class HoverGeometry implements HoverGeometryContract {
    private resting: Rect;
    private display: Rect;
    private settings: HoverSettings;
    private desiredHovered = false;
    private active = false;
    private control = false;
    private controlFrame: Rect | null = null;
    private pointer: Point | null = null;
    private isHovered = false;
    onPositionChange?: (position: Point) => void;
    constructor(frame: Rect, settings: HoverSettings, private readonly screens: () => Rect[]) {
        this.resting = { ...frame }; this.display = { ...frame }; this.settings = { ...settings };
    }
    get displayFrame(): Rect { return { ...this.display }; }
    get restingFrame(): Rect { return { ...this.resting }; }
    get hovered(): boolean { return this.isHovered; }
    pointerChanged(pointer: Point): void {
        this.pointer = { ...pointer }; this.desiredHovered = contains(this.display, pointer);
        if (!this.active) this.applyHover();
    }
    setControlHeld(held: boolean): void {
        if (this.control === held) return;
        this.control = held;
        if (!this.active) this.applyHover();
    }
    setInteractionActive(active: boolean): void { this.active = active; if (!active) this.applyHover(); }
    commitMovedFrame(frame: Rect): void {
        this.display = { ...frame };
        this.resting = clamp({ ...this.resting, x: frame.x + (frame.width - this.resting.width) / 2,
            y: frame.y + (frame.height - this.resting.height) / 2 }, this.screens());
        if (this.controlFrame) this.controlFrame = { ...this.resting };
        this.onPositionChange?.({ x: this.resting.x, y: this.resting.y });
        if (!this.active) this.applyFrame();
    }
    configure(size: Size, settings: HoverSettings): void {
        const previous = this.resting;
        this.resting = clamp({ x: previous.x + (previous.width - size.width) / 2, y: previous.y + (previous.height - size.height) / 2, ...size }, this.screens());
        this.settings = { ...settings }; this.controlFrame = null;
        if (!this.active) this.applyFrame();
        if (this.resting.x !== previous.x || this.resting.y !== previous.y) this.onPositionChange?.({ x: this.resting.x, y: this.resting.y });
    }
    place(placement: Placement): void {
        if (this.active) return;
        const screen = nearestScreen(this.resting, this.screens());
        if (!screen) return;
        const availableX = Math.max(0, screen.width - this.resting.width), availableY = Math.max(0, screen.height - this.resting.height);
        const insetX = Math.min(24, availableX / 2), insetY = Math.min(24, availableY / 2);
        const x = placement === 'center' ? availableX / 2 : placement.endsWith('Left') ? insetX : availableX - insetX;
        const y = placement === 'center' ? availableY / 2 : placement.startsWith('top') ? insetY : availableY - insetY;
        this.resting = { ...this.resting, x: screen.x + x, y: screen.y + y };
        this.controlFrame = null; this.display = { ...this.resting };
        this.desiredHovered = this.pointer !== null && contains(this.resting, this.pointer);
        this.applyHover(); this.onPositionChange?.({ x: this.resting.x, y: this.resting.y });
    }
    resetHover(): void {
        this.desiredHovered = false; this.active = false; this.control = false; this.controlFrame = null; this.applyHover();
    }
    private applyHover(): void { this.isHovered = this.desiredHovered; this.applyFrame(); }
    private applyFrame(): void {
        if (this.control && this.isHovered) {
            if (!this.controlFrame) {
                const p = this.pointer ?? { x: this.display.x + this.display.width / 2, y: this.display.y + this.display.height / 2 };
                const u = Math.max(0, Math.min(1, (p.x - this.display.x) / this.display.width));
                const v = Math.max(0, Math.min(1, (p.y - this.display.y) / this.display.height));
                this.controlFrame = clamp({ ...this.resting, x: p.x - u * this.resting.width, y: p.y - v * this.resting.height }, this.screens());
            }
            this.display = { ...this.controlFrame }; return;
        }
        this.controlFrame = null;
        const factor = this.isHovered && this.settings.isEnabled && !this.control ? this.settings.multiplier : 1;
        const width = this.resting.width * factor, height = this.resting.height * factor;
        this.display = clamp({ x: this.resting.x + (this.resting.width - width) / 2,
            y: this.resting.y + (this.resting.height - height) / 2, width, height }, this.screens());
    }
}
