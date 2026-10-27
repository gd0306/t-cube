import * as THREE from 'three';
import {
    createBodyGeometry,
    createFaceGeometry,
    ICON_RECTS,
    TEXTURE_SIZE,
    pickCube,
} from '../core/geometry';
import { applyScrollRotation, DragRotation, IdleRotation, PrismMotion } from '../core/rotation';
import { FACES, type Appearance, type Face, type Snapshot } from '../shared/contracts';
import { padTransparentRGB, subscribe, wheelDelta } from './util';
import { gestureHit } from './state';
import { createGlassMaterial, updateGlassMaterial } from './glass';

const scene = new THREE.Scene(),
    cube = new THREE.Group();
scene.add(cube);
const camera = new THREE.PerspectiveCamera(32, 1, 0.1, 100);
camera.position.z = 3.45;
const renderer = new THREE.WebGLRenderer({
    alpha: true,
    antialias: true,
    premultipliedAlpha: true,
});
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.setClearColor(0, 0);
document.body.prepend(renderer.domElement);
const idle = new IdleRotation(),
    dragRotation = new DragRotation(),
    motion = new PrismMotion();
cube.quaternion.copy(idle.orientation);
const body = createBodyGeometry();
const glass = new THREE.Mesh(body, createGlassMaterial());
glass.name = 'glass-shell';
cube.add(glass);
const pearl = new THREE.Mesh(
    body,
    new THREE.MeshBasicMaterial({ transparent: true, depthWrite: false, opacity: 0.25 * 0.55 }),
);
cube.add(pearl);
const chroma = new THREE.Mesh(
    body,
    new THREE.MeshBasicMaterial({ transparent: true, depthWrite: false, opacity: 0.25 }),
);
cube.add(chroma);
const energy = new THREE.Mesh(
    new THREE.SphereGeometry(0.26, 32, 16),
    new THREE.MeshBasicMaterial({ transparent: true, depthWrite: false, opacity: 0.025 }),
);
cube.add(energy);
const faceMaterials = new Map<Face, THREE.MeshBasicMaterial>();
for (const face of FACES) {
    const material = new THREE.MeshBasicMaterial({
        transparent: true,
        depthWrite: false,
        alphaTest: 0.005,
    });
    faceMaterials.set(face, material);
    cube.add(new THREE.Mesh(createFaceGeometry(face), material));
}
let snapshot: Snapshot | undefined,
    appearanceKey = '',
    iconKey = '',
    last = 0,
    timer = 0,
    dirty = true;
function optical(layer: 'pearl' | 'chroma' | 'energy', appearance: Appearance): THREE.DataTexture {
    const w = 512,
        h = 256,
        pixels = new Uint8Array(w * h * 4),
        a = new THREE.Color(appearance.primaryHex).convertLinearToSRGB(),
        b = new THREE.Color(appearance.secondaryHex).convertLinearToSRGB();
    const gaussian = (v: number, center: number, width: number) =>
        Math.exp(-(((v - center) / width) ** 2));
    for (let y = 0; y < h; y++)
        for (let x = 0; x < w; x++) {
            const u = x / w,
                v = 1 - y / (h - 1),
                wave = 0.5 + 0.5 * Math.cos(2 * Math.PI * u);
            let color: THREE.Color, alpha: number;
            if (layer === 'pearl') {
                color = new THREE.Color().setRGB(0.94, 0.98, 1);
                alpha =
                    (0.2 * gaussian(v, 0.7 + 0.12 * Math.cos(2 * Math.PI * u), 0.055) +
                        0.035 * gaussian(v, 0.72, 0.22)) *
                    (0.35 + 0.65 * wave * wave);
            } else {
                const mix =
                    0.5 + 0.5 * Math.sin(2 * Math.PI * (u + (layer === 'chroma' ? 0.12 : 0)));
                color = a.clone().lerp(b, mix);
                if (layer === 'energy') {
                    color.lerp(new THREE.Color(0xffffff), 0.35);
                    const first = 0.5 + 0.2 * Math.sin(4 * Math.PI * u),
                        second = 0.48 + 0.24 * Math.cos(2 * Math.PI * u + 0.8),
                        third = 0.52 + 0.18 * Math.sin(6 * Math.PI * u + 1.7);
                    alpha =
                        Math.min(
                            1,
                            0.72 *
                                (gaussian(v, first, 0.012) +
                                    gaussian(v, second, 0.014) +
                                    gaussian(v, third, 0.01)) +
                                0.06 * (gaussian(v, first, 0.045) + gaussian(v, second, 0.045)),
                        ) * gaussian(v, 0.5, 0.32);
                } else if (appearance.surfaceStyle === 'iridescent') {
                    color.lerp(
                        new THREE.Color().setRGB(1, 0.83, 0.67),
                        0.46 * Math.max(0, Math.sin(2 * Math.PI * (u - 0.18))) ** 6,
                    );
                    alpha =
                        gaussian(v, 0.38 + 0.14 * Math.sin(2 * Math.PI * u), 0.2) *
                        (0.06 + 0.09 * wave ** 4);
                } else if (appearance.surfaceStyle === 'moonstone') {
                    color.lerp(new THREE.Color(0xffffff), 0.65);
                    alpha = gaussian(v, 0.52, 0.28) * (0.04 + 0.08 * wave);
                } else if (appearance.surfaceStyle === 'aurora') {
                    color.lerp(new THREE.Color(0xffffff), 0.15);
                    alpha =
                        gaussian(v, 0.45 + 0.15 * Math.sin(2 * Math.PI * u), 0.16) *
                        (0.07 + 0.12 * wave * wave);
                } else {
                    color.lerp(new THREE.Color(0xffffff), 0.2);
                    alpha = gaussian(v, 0.42, 0.24) * (0.025 + 0.055 * wave * wave);
                }
            }
            const i = (y * w + x) * 4;
            pixels[i] = color.r * 255;
            pixels[i + 1] = color.g * 255;
            pixels[i + 2] = color.b * 255;
            pixels[i + 3] = alpha * 255;
        }
    const texture = new THREE.DataTexture(pixels, w, h, THREE.RGBAFormat);
    texture.wrapS = THREE.RepeatWrapping;
    texture.magFilter = THREE.LinearFilter;
    texture.minFilter = THREE.LinearFilter;
    texture.colorSpace = THREE.SRGBColorSpace;
    texture.needsUpdate = true;
    return texture;
}
function updateAppearance(appearance: Appearance) {
    const key = JSON.stringify(appearance);
    if (key === appearanceKey) return;
    appearanceKey = key;
    for (const [mesh, layer] of [
        [pearl, 'pearl'],
        [chroma, 'chroma'],
        [energy, 'energy'],
    ] as const) {
        const material = mesh.material;
        material.map?.dispose();
        material.map = optical(layer, appearance);
        material.needsUpdate = true;
    }
    energy.visible = appearance.surfaceStyle !== 'clear' && appearance.glowIntensity > 0;
    dirty = true;
}
let textureVersion = 0;
async function updateIcons(data: Snapshot) {
    const key = JSON.stringify([data.state.configuration.groups, data.icons]);
    if (key === iconKey) return;
    iconKey = key;
    const version = ++textureVersion;
    const images = new Map<string, HTMLImageElement>();
    await Promise.all(
        Object.entries(data.icons).map(
            ([id, url]) =>
                new Promise<void>((resolve) => {
                    const image = new Image();
                    image.onload = () => {
                        images.set(id, image);
                        resolve();
                    };
                    image.onerror = () => resolve();
                    image.src = url;
                }),
        ),
    );
    if (version !== textureVersion) return;
    for (const face of FACES) {
        const canvas = document.createElement('canvas');
        canvas.width = canvas.height = TEXTURE_SIZE;
        const ctx = canvas.getContext('2d')!;
        data.state.configuration.groups[face].slots.forEach((item, i) => {
            const image = item && images.get(item.id);
            if (image) {
                const r = ICON_RECTS[i];
                ctx.drawImage(image, r.x, r.y, r.width, r.height);
            }
        });
        const pixels = ctx.getImageData(0, 0, TEXTURE_SIZE, TEXTURE_SIZE);
        padTransparentRGB(pixels.data, TEXTURE_SIZE, TEXTURE_SIZE);
        // DataTexture preserves RGB in transparent texels, unlike a canvas upload.
        const texture = new THREE.DataTexture(
            pixels.data,
            TEXTURE_SIZE,
            TEXTURE_SIZE,
            THREE.RGBAFormat,
        );
        texture.flipY = true;
        texture.colorSpace = THREE.SRGBColorSpace;
        texture.magFilter = THREE.LinearFilter;
        texture.minFilter = THREE.LinearMipmapLinearFilter;
        texture.generateMipmaps = true;
        texture.needsUpdate = true;
        const material = faceMaterials.get(face)!;
        material.map?.dispose();
        material.map = texture;
        material.needsUpdate = true;
    }
    requestUpdate();
}
function render() {
    if (!snapshot?.state.visible || document.hidden) {
        timer = 0;
        last = 0;
        return;
    }
    const now = performance.now(),
        dt = last ? Math.min((now - last) / 1000, 0.1) : 0;
    last = now;
    const state = snapshot.state,
        paused =
            state.hovered ||
            state.interactionActive ||
            state.reducedMotion ||
            !state.configuration.autoRotatesWhenIdle;
    cube.quaternion.copy(idle.step(dt, paused));
    motion.step(dt, state.hovered, state.reducedMotion);
    updateGlassMaterial(glass.material, state.displayedAppearance, motion.engagement);
    pearl.material.map!.offset.x = -motion.phase;
    chroma.material.map!.offset.x = motion.phase;
    energy.material.map!.offset.x = motion.phase;
    pearl.material.opacity = 0.25 * (0.55 + 0.2 * motion.engagement);
    chroma.material.opacity =
        0.25 *
        state.displayedAppearance.glowIntensity *
        (0.55 + 0.25 * motion.engagement) *
        (0.94 + 0.06 * Math.sin(motion.phase * 2 * Math.PI));
    energy.material.opacity =
        0.25 *
        state.displayedAppearance.glowIntensity *
        (state.displayedAppearance.surfaceStyle === 'moonstone' ? 0.1 : 0.2) *
        (1 - 0.86 * motion.engagement);
    renderer.render(scene, camera);
    dirty = false;
    const animated =
        !state.reducedMotion &&
        (!paused ||
            state.displayedAppearance.glowIntensity > 0 ||
            Math.abs(motion.engagement - (state.hovered ? 1 : 0)) > 0.001);
    timer = animated ? window.setTimeout(render, 1000 / 30) : 0;
}
function requestUpdate() {
    dirty = true;
    if (!timer && snapshot?.state.visible && !document.hidden)
        timer = window.setTimeout(render, 1000 / 30);
}
export const controller = { scene, cube, camera, renderer, render, requestUpdate };
function resize() {
    const w = window.innerWidth,
        h = window.innerHeight;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    requestUpdate();
}
window.addEventListener('resize', resize);
document.addEventListener('visibilitychange', requestUpdate);
resize();
subscribe((data) => {
    idle.orientation.copy(dragRotation.apply(data.state.rotationDrag, idle.orientation));
    cube.quaternion.copy(idle.orientation);
    snapshot = data;
    updateAppearance(data.state.displayedAppearance);
    void updateIcons(data);
    requestUpdate();
});
window.tcube.onError((message) => {
    const status = document.querySelector<HTMLElement>('#status')!;
    status.textContent = message;
    setTimeout(() => {
        if (status.textContent === message) status.textContent = '';
    }, 5000);
});
let active: { button: 0 | 2; id: Promise<number>; ended: boolean } | null = null;
renderer.domElement.addEventListener('contextmenu', (event) => event.preventDefault());
renderer.domElement.addEventListener('pointerdown', (event) => {
    if (event.button !== 0 && event.button !== 2) return;
    if (active && !snapshot?.state.interactionActive) active = null;
    if (active) return;
    event.preventDefault();
    renderer.domElement.setPointerCapture(event.pointerId);
    const button = event.button as 0 | 2;
    active = { button, id: window.tcube.beginPointer(button), ended: false };
});
function end(event: PointerEvent) {
    const gesture = active;
    if (!gesture || gesture.ended) return;
    gesture.ended = true;
    active = null;
    const hit = gestureHit(event.type, () => {
        const rect = renderer.domElement.getBoundingClientRect();
        const raycaster = new THREE.Raycaster();
        raycaster.setFromCamera(
            new THREE.Vector2(
                ((event.clientX - rect.left) / rect.width) * 2 - 1,
                1 - ((event.clientY - rect.top) / rect.height) * 2,
            ),
            camera,
        );
        return snapshot
            ? pickCube(
                  raycaster.ray,
                  cube.quaternion,
                  !snapshot.state.configuration.expandsFacesOnClick,
              )
            : null;
    });
    void gesture.id
        .then((gestureId) =>
            window.tcube.endPointer({
                gestureId,
                button: gesture.button,
                hit,
                cancelled: event.type !== 'pointerup',
            }),
        )
        .catch(console.error);
}
renderer.domElement.addEventListener('pointerup', end);
renderer.domElement.addEventListener('pointercancel', end);
renderer.domElement.addEventListener('lostpointercapture', end);
renderer.domElement.addEventListener(
    'wheel',
    (event) => {
        event.preventDefault();
        const delta = wheelDelta(event.deltaX, event.deltaY, event.shiftKey, event.deltaMode);
        idle.orientation.copy(
            applyScrollRotation(idle.orientation, delta.dx, delta.dy, delta.precise),
        );
        cube.quaternion.copy(idle.orientation);
        requestUpdate();
    },
    { passive: false },
);
