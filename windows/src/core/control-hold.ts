export interface ControlHoldInput { available: boolean; controlHeld: boolean; interrupted: boolean }
/** One activation per clean physical press; gaps never count as held time. */
export class ControlHoldGesture {
    private released = false;
    private held = false;
    private blocked = true;
    private started = 0;
    private pendingInterruption = false;
    private sampled: number | undefined;
    reset(): void { this.released = false; this.held = false; this.blocked = true; this.sampled = undefined; this.pendingInterruption = false; }
    interrupt(): void { this.blocked = true; this.pendingInterruption = true; }
    update(input: ControlHoldInput, now: number): boolean {
        if (!input.available || (this.sampled !== undefined && (now < this.sampled || now - this.sampled > 1000))) this.reset();
        this.sampled = now;
        if (!input.available) return false;
        if (!input.controlHeld) { this.released = true; this.held = false; this.blocked = false; this.pendingInterruption = false; return false; }
        if (!this.held) { this.held = true; this.started = now; this.blocked = !this.released || input.interrupted || this.pendingInterruption; this.released = false; }
        if (input.interrupted) this.blocked = true;
        if (this.blocked || now - this.started < 1000) return false;
        this.blocked = true;
        return true;
    }
}
