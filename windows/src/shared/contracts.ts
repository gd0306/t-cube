import type { ClipboardHistoryBridge } from './clipboard-history';
import type { ProductivityBridge } from './productivity';
import type { MaintenanceBridge, LifecycleBridge } from './maintenance';
export const FACES = ['front', 'right', 'back', 'left', 'top', 'bottom'] as const;
export type Face = typeof FACES[number];
export type Placement = 'topLeft' | 'topRight' | 'bottomLeft' | 'bottomRight' | 'center';
export interface Point { x: number; y: number }
export interface Size { width: number; height: number }
export interface Rect extends Point, Size {}
export type ThemeId = 'aurora' | 'ocean' | 'sunset' | 'starfield' | 'blossom' | 'forest' | 'prism' | 'moonstone' | 'auroraFlow';
export type SurfaceStyle = 'clear' | 'iridescent' | 'moonstone' | 'aurora';
export type Material = 'glass' | 'slime';
export interface Appearance { primaryHex: string; secondaryHex: string; glowIntensity: number; surfaceStyle: SurfaceStyle; material: Material }
export interface LauncherItem { id: string; path: string; name: string; kind: 'application' | 'folder' | 'file' | 'website' | 'systemSettings' }
export type Slots = [LauncherItem | null, LauncherItem | null, LauncherItem | null, LauncherItem | null];
export interface FaceGroup { name: string; slots: Slots }
export interface HoverSettings { isEnabled: boolean; multiplier: number; delaySeconds?: number }
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
    idlePowerSaving?: boolean;
    configuration: Configuration;
    displayedAppearance: Appearance;
    activeTheme: ThemeId | null;
    hovered: boolean;
    /** Native cursor normalized to [0, 1], from the displayed frame's top-left; active slime contact only. */
    pointer: Point | null;
    controlHeld: boolean;
    interactionActive: boolean;
    rotationDrag: RotationDrag | null;
    reducedMotion: boolean;
    visible: boolean;
    expandedFace: Face | null;
    platform: string;
}
export interface RotationDrag extends Point { id: number }
export interface Snapshot { state: ViewState; icons: Record<string, string> }
export interface Hit { face: Face; slot: number | null }
export interface TargetRequest { face: Face; slot: number; kind: 'application' | 'folder' | 'file' }
export type URLTargetRequest = { face: Face; slot: number } & ({ kind: 'website'; name: string; url: string } | { kind: 'systemSettings'; settingsId: string });
export interface InstalledApplication { id: string; name: string; detail: string }
export interface DesktopBridge extends ProductivityBridge, MaintenanceBridge, LifecycleBridge, ClipboardHistoryBridge {
    getPerformanceSettings(): Promise<{idlePowerSaving:boolean}>;
    setPerformanceSettings(idlePowerSaving:boolean): Promise<void>;
    getSnapshot(): Promise<Snapshot>;
    onState(callback: (state: ViewState) => void): () => void;
    onIcons(callback: (icons: Record<string, string>) => void): () => void;
    onError(callback: (message: string) => void): () => void;
    beginPointer(button: 0 | 2): Promise<number>;
    endPointer(request: { gestureId: number; button: 0 | 2; hit: Hit | null; cancelled?: boolean }): Promise<void>;
    applyConfiguration(configuration: Configuration): Promise<void>;
    chooseTarget(request: TargetRequest): Promise<void>;
    addURLTarget(request: URLTargetRequest): Promise<void>;
    listInstalledApplications(refresh?: boolean): Promise<InstalledApplication[]>;
    installedApplicationIcons(ids: string[]): Promise<Record<string, string>>;
    addInstalledApplication(request: { face: Face; slot: number; applicationId: string }): Promise<void>;
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
