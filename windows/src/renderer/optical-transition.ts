import { DataTexture, MeshBasicMaterial, RGBAFormat } from 'three';
import { blendTexturePixels } from '../core/theme-transition';

/** Blends maps on the same geometry/UVs, so native hover and rotation never leave a second pose. */
export class OpticalTransition {
    readonly uniforms = {
        previousMap: { value: null as DataTexture | null },
        themeProgress: { value: 1 },
        previousOpacity: { value: 1 },
        targetOpacity: { value: 1 },
    };
    private from?: DataTexture;
    private target?: DataTexture;
    private fromOpacity = 1;
    private targetOpacity = 1;

    constructor(private readonly material: MeshBasicMaterial) {
        material.onBeforeCompile = shader => {
            Object.assign(shader.uniforms, this.uniforms);
            shader.fragmentShader = `uniform sampler2D previousMap;\nuniform float themeProgress;\nuniform float previousOpacity;\nuniform float targetOpacity;\n${shader.fragmentShader}`
                .replace('#include <map_fragment>', `
                    #ifdef USE_MAP
                        vec4 oldSample = texture2D(previousMap, vMapUv);
                        vec4 newSample = texture2D(map, vMapUv);
                        oldSample.a *= previousOpacity;
                        newSample.a *= targetOpacity;
                        // Samples are linear RGB. Interpolate their premultiplied contributions,
                        // then restore straight RGB for MeshBasicMaterial's normal alpha blend.
                        float mixedAlpha = mix(oldSample.a, newSample.a, themeProgress);
                        vec3 mixedRGB = mix(oldSample.rgb * oldSample.a, newSample.rgb * newSample.a, themeProgress);
                        diffuseColor *= vec4(mixedAlpha > 0.0 ? mixedRGB / mixedAlpha : vec3(0.0), mixedAlpha);
                    #endif
                `);
        };
        material.customProgramCacheKey = () => 'optical-premultiplied-theme-v1';
    }

    retarget(target: DataTexture, previousProgress: number, animate: boolean, opacity = 1): void {
        const hadMap = Boolean(this.target);
        let source = this.target;
        let sourceOpacity = this.targetOpacity;
        if (animate && this.from && previousProgress < 1) {
            if (previousProgress <= 0) {
                source = this.from;
                sourceOpacity = this.fromOpacity;
            }
            else {
                const image = this.target!.image;
                source = new DataTexture(
                    blendTexturePixels(this.from.image.data as Uint8Array, image.data as Uint8Array, previousProgress, this.fromOpacity, this.targetOpacity),
                    image.width, image.height, RGBAFormat,
                );
                source.wrapS = target.wrapS;
                source.wrapT = target.wrapT;
                source.magFilter = target.magFilter;
                source.minFilter = target.minFilter;
                source.colorSpace = target.colorSpace;
                source.needsUpdate = true;
                sourceOpacity = 1;
            }
        }
        const retained = animate ? source : undefined;
        for (const map of new Set([this.from, this.target])) if (map && map !== retained) map.dispose();
        this.from = retained;
        this.target = target;
        this.fromOpacity = sourceOpacity;
        this.targetOpacity = Math.max(0, Math.min(1, opacity));
        this.material.map = target;
        this.uniforms.previousMap.value = retained ?? target;
        this.uniforms.themeProgress.value = retained ? 0 : 1;
        this.uniforms.previousOpacity.value = retained ? sourceOpacity : this.targetOpacity;
        this.uniforms.targetOpacity.value = this.targetOpacity;
        if (!hadMap) this.material.needsUpdate = true;
    }

    update(progress: number): void {
        this.uniforms.themeProgress.value = Math.max(0, Math.min(1, progress));
        if (progress >= 1 && this.from) {
            this.from.dispose();
            this.from = undefined;
            this.uniforms.previousMap.value = this.target!;
            this.uniforms.previousOpacity.value = this.targetOpacity;
        }
    }

    dispose(): void {
        for (const map of new Set([this.from, this.target])) map?.dispose();
        this.from = this.target = undefined;
        this.uniforms.previousMap.value = null;
        this.material.map = null;
    }
}
