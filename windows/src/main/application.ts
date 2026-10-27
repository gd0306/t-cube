import { addTarget, moveTarget, normalizeConfiguration, removeTarget, renameGroup, resolveAppearance } from '../core/configuration';
import { HoverGeometry } from '../core/hover';
import type { ConfigurationStore } from '../core/store';
import type { InputState } from '../native/win32';
import type { Configuration, Face, Hit, LauncherItem, Placement, Point, Rect, Snapshot, TargetRequest, ViewState } from '../shared/contracts';

export interface HostServices {
    platform: string;
    cursor(): Point;
    input(): InputState;
    screens(): Rect[];
    setFrame(frame: Rect): void;
    setVisible(visible: boolean): void;
    openPath(path: string): Promise<string>;
    showSettings(): void;
    showExpanded(face: Face): void;
    closeExpanded(): void;
    stateChanged(state: ViewState): void;
    iconsChanged(icons: Record<string, string>): void;
    error(message: string): void;
    validateTarget(path: string, kind?: LauncherItem['kind']): Promise<LauncherItem>;
    chooseTarget(request: TargetRequest): Promise<string[]>;
    quit(): void;
    refreshIcons(configuration: Configuration): Promise<Record<string, string>>;
}
interface Gesture {
    id: number; button: 0 | 2; origin: Point; frame: Rect; movedFrame: Rect;
    dragged: boolean; moveOnly: boolean; released: boolean; releasedAt: number;
    hit: Hit | null | undefined;
}

/** Application state is independent of Electron, so input and persistence can be verified without opening other apps. */
export class LauncherHost {
    readonly geometry: HoverGeometry;
    private configuration: Configuration;
    private gesture: Gesture | null = null;
    private sequence = 0;
    private visible = true;
    private reducedMotion = false;
    private controlHeld = false;
    private expandedFace: Face | null = null;
    private icons: Record<string, string> = {};
    private lastState = '';
    private lastFrame = '';
    private elapsed = 0;
    private iconGeneration = 0;
    private position: Point | null = null;
    private readonly pendingSideEffects = new Set<Promise<void>>();
    private readonly pendingPersistence = new Set<Promise<unknown>>();
    constructor(private readonly store: ConfigurationStore, private readonly services: HostServices) {
        this.configuration = store.snapshot;
        const size = 164 * this.configuration.scale;
        this.geometry = new HoverGeometry({ ...(this.configuration.windowPosition ?? { x: 120, y: 120 }), width: size, height: size }, this.configuration.hover, services.screens);
        this.geometry.onPositionChange = point => { this.position = point; };
        this.publish();
    }
    get snapshot(): Snapshot {
        const resolved = resolveAppearance(this.configuration, this.elapsed);
        return { state: { configuration: structuredClone(this.configuration), displayedAppearance: resolved.appearance,
            activeTheme: resolved.theme, hovered: this.geometry.hovered, controlHeld: this.controlHeld,
            interactionActive: Boolean(this.gesture && !this.gesture.released), reducedMotion: this.reducedMotion,
            visible: this.visible, expandedFace: this.expandedFace, platform: this.services.platform }, icons: { ...this.icons } };
    }
    reportError(error: unknown): void { this.services.error(error instanceof Error ? error.message : String(error)); }
    async refreshIcons(): Promise<void> {
        const generation = ++this.iconGeneration;
        const icons = await this.services.refreshIcons(this.configuration);
        if (generation !== this.iconGeneration) return;
        this.icons = icons; this.services.iconsChanged({ ...icons });
    }
    private publish(): void {
        const gesture = this.gesture;
        const frame = gesture && !gesture.released && gesture.dragged ? gesture.movedFrame : this.geometry.displayFrame;
        const frameKey = JSON.stringify(frame);
        if (frameKey !== this.lastFrame) { this.lastFrame = frameKey; this.services.setFrame(frame); }
        const state = this.snapshot.state, key = JSON.stringify(state);
        if (key !== this.lastState) { this.lastState = key; this.services.stateChanged(state); }
    }
    private async update(edit: (config: Configuration) => Configuration | void): Promise<void> {
        const pending = this.store.update(edit);
        this.pendingPersistence.add(pending);
        try { this.configuration = await pending; this.publish(); }
        finally { this.pendingPersistence.delete(pending); }
    }
    private async savePosition(): Promise<void> {
        if (!this.position) return;
        const point = this.position; this.position = null;
        await this.update(config => { config.windowPosition = point; });
    }
    private detach(task: Promise<void>, persists = false): void {
        const tracked = task.catch(error => this.reportError(error));
        this.pendingSideEffects.add(tracked);
        if (persists) this.pendingPersistence.add(tracked);
        void tracked.then(() => { this.pendingSideEffects.delete(tracked); this.pendingPersistence.delete(tracked); });
    }
    /** Drain input-triggered work for orderly lifecycle completion without blocking native sampling. */
    async whenIdle({ includeLaunches = true }: { includeLaunches?: boolean } = {}): Promise<void> {
        while (true) {
            const pending = new Set([...this.pendingPersistence, ...(includeLaunches ? this.pendingSideEffects : [])]);
            if (!pending.size) return;
            await Promise.allSettled(pending);
        }
    }
    poll(elapsedSeconds = this.elapsed, reducedMotion = this.reducedMotion): void {
        this.elapsed = elapsedSeconds; this.reducedMotion = reducedMotion;
        const input = this.services.input(), pointer = this.services.cursor();
        // macOS preview updates Control using before-input-event instead of unavailable Win32 polling.
        if (input.available) this.controlHeld = input.controlHeld;
        this.geometry.pointerChanged(pointer); this.geometry.setControlHeld(this.controlHeld);
        const gesture = this.gesture;
        if (gesture && !gesture.released) {
            gesture.moveOnly ||= this.controlHeld;
            const dx = pointer.x - gesture.origin.x, dy = pointer.y - gesture.origin.y;
            if (Math.hypot(dx, dy) >= 5) gesture.dragged = true;
            if (gesture.dragged) {
                gesture.movedFrame = { ...gesture.frame, x: gesture.frame.x + dx, y: gesture.frame.y + dy };
                this.services.setFrame(gesture.movedFrame); this.lastFrame = JSON.stringify(gesture.movedFrame);
            }
            if (input.available && !(gesture.button === 0 ? input.primaryDown : input.secondaryDown)) this.release(gesture);
        }
        if (this.gesture?.released && this.gesture.button === 2 && this.gesture.hit === undefined
            && Date.now() - this.gesture.releasedAt >= 150) this.dispatchClick(this.gesture);
        if (this.gesture?.released && Date.now() - this.gesture.releasedAt > 1500) this.gesture = null;
        // During a drag the platform frame follows the pointer; hover remains frozen until release.
        if (!this.gesture || this.gesture.released || !this.gesture.dragged) this.publish();
        else {
            const state = this.snapshot.state, key = JSON.stringify(state);
            if (key !== this.lastState) { this.lastState = key; this.services.stateChanged(state); }
        }
        if (this.position) this.detach(this.savePosition(), true);
    }
    setFallbackControl(held: boolean): void { this.controlHeld = held; this.geometry.setControlHeld(held); this.publish(); }
    beginPointer(button: 0 | 2): number {
        if (this.gesture && !this.gesture.released) return this.gesture.id;
        this.closeExpanded();
        const input = this.services.input();
        if (input.available) this.controlHeld = input.controlHeld;
        const origin = this.services.cursor();
        this.geometry.pointerChanged(origin); this.geometry.setControlHeld(this.controlHeld);
        const frame = this.geometry.displayFrame;
        this.geometry.setInteractionActive(true);
        this.gesture = { id: ++this.sequence, button, origin, frame, movedFrame: frame, dragged: false,
            moveOnly: this.controlHeld, released: false, releasedAt: 0, hit: undefined };
        this.publish(); return this.gesture.id;
    }
    async endPointer(request: { gestureId: number; button: 0 | 2; hit: Hit | null; cancelled?: boolean }): Promise<void> {
        const gesture = this.gesture;
        if (!gesture || gesture.id !== request.gestureId || gesture.button !== request.button || gesture.hit !== undefined) return;
        if (gesture.released && Date.now() - gesture.releasedAt > 1500) { this.gesture = null; return; }
        gesture.moveOnly ||= request.cancelled === true;
        gesture.hit = request.hit;
        if (!this.services.input().available && !gesture.released) {
            this.poll(); // Sample final displacement before the fallback mouseup.
            this.release(gesture);
        } else if (gesture.released) this.dispatchClick(gesture);
    }
    private release(gesture: Gesture): void {
        if (gesture.released) return;
        gesture.released = true; gesture.releasedAt = Date.now();
        if (gesture.dragged) {
            this.geometry.commitMovedFrame(gesture.movedFrame);
            // Refresh desired hover against the moved display while hover geometry is still frozen.
            this.geometry.pointerChanged(this.services.cursor());
        }
        this.geometry.setInteractionActive(false);
        this.publish();
        if (this.position) this.detach(this.savePosition(), true);
        if (gesture.hit !== undefined || gesture.dragged || gesture.moveOnly) this.dispatchClick(gesture);
    }
    private dispatchClick(gesture: Gesture): void {
        if (this.gesture !== gesture) return;
        this.gesture = null;
        if (gesture.dragged || gesture.moveOnly) return;
        if (gesture.button === 2) { this.showSettings(); return; }
        if (!gesture.hit) return;
        if (this.configuration.expandsFacesOnClick) {
            this.expandedFace = gesture.hit.face; this.services.showExpanded(gesture.hit.face); this.publish();
        } else if (gesture.hit.slot !== null) this.detach(this.launch({ face: gesture.hit.face, slot: gesture.hit.slot }));
    }
    async applyConfiguration(input: Configuration): Promise<void> {
        // Renderers may change preferences, but only explicit target operations can edit groups.
        await this.update(current => normalizeConfiguration({ ...input, groups: current.groups, windowPosition: current.windowPosition }));
        const size = 164 * this.configuration.scale;
        this.geometry.configure({ width: size, height: size }, this.configuration.hover);
        await this.savePosition(); this.publish();
    }
    async chooseTarget(request: TargetRequest): Promise<void> {
        const paths = await this.services.chooseTarget(request);
        if (!paths.length) return;
        const item = await this.services.validateTarget(paths[0], request.kind);
        await this.update(config => addTarget(config, request.face, item, request.slot, true));
        await this.refreshIcons();
    }
    async dropTargets(request: { paths: string[]; face: Face; slot?: number }): Promise<void> {
        const items = await Promise.all(request.paths.map(value => this.services.validateTarget(value)));
        await this.update(config => {
            let next = config;
            items.forEach((item, index) => { next = addTarget(next, request.face, item, index === 0 ? request.slot : undefined, index === 0 && request.slot !== undefined); });
            return next;
        });
        await this.refreshIcons();
    }
    async removeTarget(request: { face: Face; slot: number }): Promise<void> {
        await this.update(config => removeTarget(config, request.face, request.slot)); await this.refreshIcons();
    }
    async moveTarget(request: { face: Face; source: number; destination: number }): Promise<void> {
        await this.update(config => moveTarget(config, request.face, request.source, request.destination));
    }
    async renameGroup(request: { face: Face; name: string }): Promise<void> { await this.update(config => renameGroup(config, request.face, request.name)); }
    async launch(request: { face: Face; slot: number }): Promise<void> {
        if (this.controlHeld) return;
        const item = this.configuration.groups[request.face].slots[request.slot];
        if (!item) throw new Error('This slot is empty');
        // Close the initiating popup before awaiting services, so a slow launch cannot close a later popup.
        this.closeExpanded();
        // Validate saved paths again: edited config files must not become a command/URL channel.
        await this.services.validateTarget(item.path, item.kind);
        const error = await this.services.openPath(item.path);
        if (error) throw new Error(`Could not open ${item.name}: ${error}`);
    }
    async place(placement: Placement): Promise<void> {
        if (this.gesture && !this.gesture.released) return;
        this.closeExpanded(); this.setVisible(true);
        this.geometry.place(placement); await this.savePosition(); this.publish();
    }
    async refreshDisplays(): Promise<void> {
        const size = 164 * this.configuration.scale;
        this.geometry.configure({ width: size, height: size }, this.configuration.hover);
        await this.savePosition(); this.publish();
    }
    showSettings(): void { this.closeExpanded(); this.services.showSettings(); }
    closeExpanded(): void { if (this.expandedFace !== null) { this.expandedFace = null; this.services.closeExpanded(); this.publish(); } }
    setVisible(visible: boolean): void {
        this.visible = visible;
        if (!visible) { this.gesture = null; this.geometry.resetHover(); this.closeExpanded(); }
        this.services.setVisible(visible);
        this.publish();
    }
    quit(): void { this.services.quit(); }
}
