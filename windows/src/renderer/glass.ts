import { Color, FrontSide, ShaderMaterial } from 'three';
import type { Appearance } from '../shared/contracts';

/** View-dependent reflections stay visible without an environment map or edge rails. */
export function createGlassMaterial(): ShaderMaterial {
    return new ShaderMaterial({
        name: 'glass-contour',
        transparent: true,
        depthWrite: false,
        side: FrontSide,
        toneMapped: false,
        uniforms: {
            primary: { value: new Color('#65DEFF') },
            secondary: { value: new Color('#B793FF') },
            glow: { value: 0.55 },
            engagement: { value: 0 },
            slime: { value: 0 },
        },
        vertexShader: `
            varying vec3 viewNormal;
            varying vec3 towardCamera;
            void main() {
                vec4 viewPosition = modelViewMatrix * vec4(position, 1.0);
                viewNormal = normalize(normalMatrix * normal);
                towardCamera = -viewPosition.xyz;
                gl_Position = projectionMatrix * viewPosition;
            }
        `,
        fragmentShader: `
            uniform vec3 primary;
            uniform vec3 secondary;
            uniform float glow;
            uniform float engagement;
            uniform float slime;
            varying vec3 viewNormal;
            varying vec3 towardCamera;
            void main() {
                vec3 normal = normalize(viewNormal);
                float grazing = 1.0 - clamp(dot(normal, normalize(towardCamera)), 0.0, 1.0);
                float rim = pow(grazing, 2.0);
                vec3 tint = mix(primary, secondary, 0.5 + 0.5 * normal.x);
                vec3 reflection = mix(vec3(0.92, 0.96, 1.0), tint, 0.68 + 0.12 * glow);
                // A narrow dark refraction at the silhouette also reads on pale desktops.
                float outer = smoothstep(0.30, 0.90, grazing);
                reflection = mix(reflection, vec3(0.025, 0.04, 0.065), outer * 0.92);
                float alpha = 0.10 + rim * (0.42 + 0.035 * engagement);
                vec3 light = normalize(vec3(-0.5, 0.8, 1.0));
                float wet = pow(max(dot(reflect(-light, normal), normalize(towardCamera)), 0.0), 36.0);
                vec3 gel = mix(tint, vec3(1.0), 0.04) + vec3(0.35 * wet);
                float gelAlpha = 0.34 + rim * 0.32 + wet * 0.16;
                gl_FragColor = vec4(mix(reflection, gel, slime), mix(alpha, gelAlpha, slime));
                #include <colorspace_fragment>
            }
        `,
    });
}

export function updateGlassMaterial(material: ShaderMaterial, appearance: Appearance, engagement: number): void {
    material.uniforms.primary.value.set(appearance.primaryHex);
    material.uniforms.secondary.value.set(appearance.secondaryHex);
    material.uniforms.glow.value = appearance.glowIntensity;
    material.uniforms.engagement.value = engagement;
    material.uniforms.slime.value = appearance.material === 'slime' ? 1 : 0;
}
