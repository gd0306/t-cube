export const FACES = ['front', 'right', 'back', 'left', 'top', 'bottom'] as const;
export type Face = typeof FACES[number];
export type Placement = 'topLeft' | 'topRight' | 'bottomLeft' | 'bottomRight' | 'center';
export interface Point { x: number; y: number }
export interface Size { width: number; height: number }
export interface Rect extends Point, Size {}
export type ThemeId = 'aurora' | 'ocean' | 'sunset' | 'starfield' | 'blossom' | 'forest' | 'prism' | 'moonstone' | 'auroraFlow';
export type SurfaceStyle = 'clear' | 'iridescent' | 'moonstone' | 'aurora';
export interface Appearance { primaryHex: string; secondaryHex: string; glowIntensity: number; surfaceStyle: SurfaceStyle }
export interface LauncherItem { id: string; path: string; name: string; kind: 'application' | 'folder' }
export type Slots = [LauncherItem | null, LauncherItem | null, LauncherItem | null, LauncherItem | null];
export interface FaceGroup { name: string; slots: Slots }
export interface HoverSettings { isEnabled: boolean; multiplier: number }
export interface Configuration {
    version: 1;
    groups: Record<Face, FaceGroup>;
    appearance: Appearance;
    themeCycle: { isEnabled: boolean; themes: ThemeId[]; intervalSeconds: 10 | 20 };
    hover: HoverSettings;
    expandsFacesOnClick: boolean;
    autoRotatesWhenIdle: boolean;
    scale: number;
    windowPosition: Point | null;
}
export interface ViewState {
    configuration: Configuration;
    displayedAppearance: Appearance;
    activeTheme: ThemeId | null;
    hovered: boolean;
    controlHeld: boolean;
    interactionActive: boolean;
    reducedMotion: boolean;
    visible: boolean;
    expandedFace: Face | null;
    platform: string;
}
export interface Snapshot { state: ViewState; icons: Record<string, string> }
export interface Hit { face: Face; slot: number | null }
export interface TargetRequest { face: Face; slot: number; kind: 'application' | 'folder' }
export interface DesktopBridge {
    getSnapshot(): Promise<Snapshot>;
    onState(callback: (state: ViewState) => void): () => void;
    onIcons(callback: (icons: Record<string, string>) => void): () => void;
    onError(callback: (message: string) => void): () => void;
    beginPointer(button: 0 | 2): Promise<number>;
    endPointer(request: { gestureId: number; button: 0 | 2; hit: Hit | null; cancelled?: boolean }): Promise<void>;
    applyConfiguration(configuration: Configuration): Promise<void>;
    chooseTarget(request: TargetRequest): Promise<void>;
    dropTargets(request: { paths: string[]; face: Face; slot?: number }): Promise<void>;
    removeTarget(request: { face: Face; slot: number }): Promise<void>;
    moveTarget(request: { face: Face; source: number; destination: number }): Promise<void>;
    renameGroup(request: { face: Face; name: string }): Promise<void>;
    launch(request: { face: Face; slot: number }): Promise<void>;
    place(placement: Placement): Promise<void>;
    showSettings(): Promise<void>;
    quit(): Promise<void>;
    closeExpanded(): Promise<void>;
    getDroppedPaths(files: File[]): string[];
}
declare global { interface Window { tcube: DesktopBridge } }

/** Pure hover controller contract. Frames and pointer coordinates are global DIP. */
export interface HoverGeometryContract {
    readonly displayFrame: Rect;
    readonly restingFrame: Rect;
    readonly hovered: boolean;
    pointerChanged(pointer: Point): void;
    setControlHeld(held: boolean): void;
    setInteractionActive(active: boolean): void;
    commitMovedFrame(frame: Rect): void;
    configure(size: Size, settings: HoverSettings): void;
    place(placement: Placement): void;
    resetHover(): void;
}
