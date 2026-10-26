import { Quaternion, Vector3 } from 'three';
import { DISPLAY_TILT } from './geometry';

export function applyScrollRotation(quaternion: Quaternion, dx: number, dy: number, precise: boolean): Quaternion {
    if (!Number.isFinite(dx) || !Number.isFinite(dy)) return quaternion.clone();
    const x = precise ? Math.max(-100, Math.min(100, -dx)) : -Math.sign(dx);
    const y = precise ? Math.max(-100, Math.min(100, dy)) : Math.sign(dy);
    const factor = precise ? 0.022 : Math.PI / 2;
    const logical = DISPLAY_TILT.clone().invert().multiply(quaternion);
    const yaw = new Quaternion().setFromAxisAngle(new Vector3(0, 1, 0), x * factor);
    const pitch = new Quaternion().setFromAxisAngle(new Vector3(1, 0, 0), -y * factor);
    return DISPLAY_TILT.clone().multiply(yaw).multiply(pitch).multiply(logical).normalize();
}

/** Seeded smooth spherical angular drift. Only active, bounded frame time advances it. */
export class IdleRotation {
    orientation = DISPLAY_TILT.clone();
    private state: bigint;
    private from: Vector3;
    private to: Vector3;
    private elapsed = 0;
    private duration: number;
    constructor(seed: number | bigint = Date.now()) {
        this.state = BigInt(seed); this.from = this.velocity(); this.to = this.velocity(); this.duration = 5 + 4 * this.random();
    }
    private random(): number {
        const mask = (1n << 64n) - 1n;
        this.state = (this.state + 0x9E3779B97F4A7C15n) & mask;
        let value = this.state;
        value = ((value ^ (value >> 30n)) * 0xBF58476D1CE4E5B9n) & mask;
        value = ((value ^ (value >> 27n)) * 0x94D049BB133111EBn) & mask;
        value ^= value >> 31n;
        return Number(value >> 11n) / 9007199254740992;
    }
    private velocity(): Vector3 {
        const z = 2 * this.random() - 1, azimuth = 2 * Math.PI * this.random();
        const radius = Math.sqrt(Math.max(0, 1 - z * z)), speed = 0.09 + 0.09 * this.random();
        return new Vector3(radius * Math.cos(azimuth), radius * Math.sin(azimuth), z).multiplyScalar(speed);
    }
    step(dt: number, paused: boolean): Quaternion {
        if (paused || !Number.isFinite(dt) || dt <= 0) return this.orientation.clone();
        const delta = Math.min(dt, 0.1); this.elapsed += delta;
        if (this.elapsed >= this.duration) {
            this.elapsed -= this.duration; this.from = this.to; this.to = this.velocity(); this.duration = 5 + 4 * this.random();
        }
        const t = this.elapsed / this.duration, blend = t * t * (3 - 2 * t);
        const velocity = this.from.clone().lerp(this.to, blend), speed = velocity.length();
        if (speed > 0.000001) this.orientation.premultiply(new Quaternion().setFromAxisAngle(velocity.divideScalar(speed), speed * delta)).normalize();
        return this.orientation.clone();
    }
}

export class PrismMotion {
    phase = 0;
    engagement = 0;
    step(dt: number, hovered: boolean, reducedMotion: boolean): void {
        if (!Number.isFinite(dt) || dt <= 0) return;
        const target = hovered ? 1 : 0;
        if (reducedMotion) { this.engagement = target; return; }
        const delta = Math.min(dt, 0.1);
        this.phase = (this.phase + delta / 18) % 1;
        this.engagement += (target - this.engagement) * (1 - Math.exp(-delta / 0.16));
        if (Math.abs(target - this.engagement) < 0.001) this.engagement = target;
    }
}
