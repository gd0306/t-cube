import type { Point, Rect } from '../shared/contracts';
const contains = (r: Rect, p: Point): boolean => p.x >= r.x && p.x < r.x + r.width && p.y >= r.y && p.y < r.y + r.height;
export function edgeHandle(frame: Rect, displays: Rect[], physicalDisplays: Rect[] = displays): Rect | null {
    const center = {x: frame.x + frame.width / 2, y: frame.y + frame.height / 2};
    const work = displays.find(display => contains(display, center));
    if (!work) return null;
    const left = Math.abs(frame.x - work.x) <= 32;
    const right = Math.abs(frame.x + frame.width - work.x - work.width) <= 32;
    if (!left && !right) return null;
    const edge = left ? work.x : work.x + work.width;
    const physical = physicalDisplays.find(display => contains(display, center)) ?? work;
    const physicalEdge = left ? physical.x : physical.x + physical.width;
    const adjoining = physicalDisplays.some(other => other !== physical && Math.abs((left ? other.x + other.width : other.x) - physicalEdge) <= 1
        && other.y < frame.y + frame.height && other.y + other.height > frame.y);
    if (adjoining) return null;
    return {x: left ? edge : edge - 10, y: Math.max(work.y, Math.min(center.y - 28, work.y + work.height - 56)), width: 10, height: 56};
}
export function isFullscreenOnDisplay(frame: Rect | null, display: Rect): boolean {
    return Boolean(frame && Math.abs(frame.x - display.x) <= 2 && Math.abs(frame.y - display.y) <= 2
        && Math.abs(frame.width - display.width) <= 2 && Math.abs(frame.height - display.height) <= 2);
}
export interface PresentationInput {frame: Rect; displays: Rect[]; physicalDisplays?: Rect[]; cursor: Point; enabled: boolean; fullscreen: boolean; manualVisible: boolean; protected: boolean; edgeHovered?: boolean; now: number}
/** Presentation never owns or edits the user's resting geometry or visibility intent. */
export class DesktopPresentation {
    private outsideSince: number | undefined;
    private collapsed = false;
    private geometry = '';
    private fullscreenRevealed = false;
    reveal(): void { this.reset(); this.fullscreenRevealed = true; }
    reset(): void { this.outsideSince = undefined; this.collapsed = false; }
    update(input: PresentationInput): {visible: boolean; collapsed: boolean; handle: Rect | null} {
        const handle = input.enabled ? edgeHandle(input.frame, input.displays, input.physicalDisplays) : null;
        if (!input.fullscreen || !input.manualVisible) this.fullscreenRevealed = false;
        const fullscreenHidden = input.fullscreen && !this.fullscreenRevealed && !input.protected;
        const geometry = JSON.stringify([input.frame, input.displays, input.physicalDisplays]);
        if (geometry !== this.geometry) { this.geometry = geometry; this.reset(); }
        if (!input.manualVisible || fullscreenHidden || input.protected || input.edgeHovered || !handle) this.reset();
        else if (contains(input.frame, input.cursor) || contains(handle, input.cursor)) this.reset();
        else { this.outsideSince ??= input.now; if (input.now - this.outsideSince >= 800) this.collapsed = true; }
        return {visible: input.manualVisible && !fullscreenHidden && !this.collapsed, collapsed: this.collapsed, handle: this.collapsed ? handle : null};
    }
}
/** Windows can enlarge translucent HWNDs at some DPIs; clip that container to the unchanged logical handle. */
export function edgeHandleWindowLayout(handle:Rect,nativeSize:{width:number;height:number},work:Rect):{frame:Rect;shape:Rect}{
    const width=Math.max(handle.width,nativeSize.width),height=Math.max(handle.height,nativeSize.height);
    const left=Math.abs(handle.x-work.x)<=1;
    const x=left?handle.x:handle.x+handle.width-width;
    const y=Math.max(work.y,Math.min(handle.y,work.y+work.height-height));
    return {frame:{x,y,width,height},shape:{x:handle.x-x,y:handle.y-y,width:handle.width,height:handle.height}};
}

/** Hover enlargement protects only edge collapse; fullscreen yields only to deliberate interaction or settings. */
export function presentationProtection(state:{interactionActive:boolean;expandedFace:string|null;hovered:boolean},settingsVisible:boolean):{protected:boolean;edgeHovered:boolean}{
    return {protected:state.interactionActive || state.expandedFace!==null || settingsVisible,edgeHovered:state.hovered};
}
