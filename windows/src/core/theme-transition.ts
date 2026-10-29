import type { Appearance } from '../shared/contracts';

type RGB = [number, number, number];
type RGBA = [number, number, number, number];
export interface ThemePalette {
    primary: RGB;
    secondary: RGB;
    glow: number;
    energy: number;
}
const clamp = (value: number) => Math.max(0, Math.min(1, value));
const linear = (value: number) => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
const srgb = (value: number) => value <= 0.0031308 ? value * 12.92 : 1.055 * value ** (1 / 2.4) - 0.055;
const linearByte = Float64Array.from({ length: 256 }, (_, value) => linear(value / 255));
function color(hex: string): RGB {
    return [1, 3, 5].map(offset => linear(parseInt(hex.slice(offset, offset + 2), 16) / 255)) as RGB;
}
function palette(appearance: Appearance): ThemePalette {
    return { primary: color(appearance.primaryHex), secondary: color(appearance.secondaryHex),
        glow: clamp(appearance.glowIntensity),
        energy: clamp(appearance.glowIntensity) * (appearance.surfaceStyle === 'clear' ? 0 : appearance.surfaceStyle === 'moonstone' ? 0.1 : 0.2) };
}
const lerp = (from: number, to: number, t: number) => from + (to - from) * t;

/** Wall-clock timing lets a hidden/paused renderer finish without a long catch-up animation. */
export class ThemeTransition {
    private from?: ThemePalette;
    private target?: ThemePalette;
    private material?: Appearance['material'];
    private started = 0;
    private finished = true;

    retarget(appearance: Appearance, now: number, reducedMotion: boolean): void {
        const current = this.target && this.sample(now);
        this.target = palette(appearance);
        this.from = current ?? this.target;
        this.finished = !current || reducedMotion || appearance.material !== this.material;
        this.material = appearance.material;
        this.started = now;
    }
    progress(now: number): number {
        if (this.finished) return 1;
        const t = clamp((now - this.started) / 400);
        return t * t * (3 - 2 * t);
    }
    active(now: number): boolean { return this.progress(now) < 1; }
    finish(): void { this.finished = true; }
    sample(now: number): ThemePalette {
        const t = this.progress(now), from = this.from!, target = this.target!;
        return {
            primary: from.primary.map((v, i) => lerp(v, target.primary[i], t)) as RGB,
            secondary: from.secondary.map((v, i) => lerp(v, target.secondary[i], t)) as RGB,
            glow: lerp(from.glow, target.glow, t), energy: lerp(from.energy, target.energy, t),
        };
    }
}

/** Straight RGBA in/out, linear RGB inside; convex premultiplied mixing avoids bright/opaque overshoot. */
export function blendPremultiplied(from: RGBA, to: RGBA, progress: number): RGBA {
    const t = clamp(progress), alpha = lerp(from[3], to[3], t);
    return alpha > 0
        ? [0, 1, 2].map(i => lerp(from[i] * from[3], to[i] * to[3], t) / alpha).concat(alpha) as RGBA
        : [0, 0, 0, 0];
}

/** Only used when retargeting an unfinished texture blend, never during animation frames. */
export function blendTexturePixels(from: Uint8Array, to: Uint8Array, progress: number, fromOpacity = 1, toOpacity = 1): Uint8Array {
    if (from.length !== to.length || from.length % 4) throw new Error('Optical texture dimensions must match');
    const result = new Uint8Array(from.length);
    const t = clamp(progress), oldOpacity = clamp(fromOpacity), newOpacity = clamp(toOpacity);
    for (let i = 0; i < from.length; i += 4) {
        const oldAlpha = from[i + 3] / 255 * oldOpacity * (1 - t), newAlpha = to[i + 3] / 255 * newOpacity * t;
        const alpha = oldAlpha + newAlpha;
        if (alpha > 0) for (let channel = 0; channel < 3; channel++) {
            const value = (linearByte[from[i + channel]] * oldAlpha + linearByte[to[i + channel]] * newAlpha) / alpha;
            result[i + channel] = Math.round(clamp(srgb(value)) * 255);
        }
        result[i + 3] = Math.round(alpha * 255);
    }
    return result;
}
