import { animationCadence } from '../core/render-policy';
import * as THREE from 'three';
import {
    createBodyGeometry,
    createFaceGeometry,
    ICON_RECTS,
    TEXTURE_SIZE,
    pickCube,
    pickSurfacePoint,
} from '../core/geometry';
import { SlimeMotion } from '../core/slime';
import { SlimeShell } from '../core/slime-geometry';
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
let slimeShell: SlimeShell | undefined;
let slime = new SlimeMotion();
let physicalMaterial: Appearance['material'] = 'glass';
const contactRay = new THREE.Raycaster();
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
                const soft = appearance.material === 'slime';
                alpha =
                    ((soft ? 0.68 : 0.2) * gaussian(v, 0.7 + 0.12 * Math.cos(2 * Math.PI * u), soft ? 0.045 : 0.055) +
                        (soft ? 0.10 : 0.035) * gaussian(v, 0.72, soft ? 0.20 : 0.22)) *
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
    if (appearance.material !== physicalMaterial) {
        physicalMaterial = appearance.material;
        slime = new SlimeMotion();
        if (physicalMaterial === 'slime') slimeShell ??= new SlimeShell(body);
        slimeShell?.reset();
        const geometry = physicalMaterial === 'slime' ? slimeShell!.geometry : body;
        for (const mesh of [glass, pearl, chroma]) mesh.geometry = geometry;
    }
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
const metrics = { frames: 0, cadence: 0 };
function render() {
    timer = 0;
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
            !state.configuration.autoRotatesWhenIdle || (state.idlePowerSaving !== false && !state.hovered);
    cube.quaternion.copy(idle.step(dt, paused));
    const phase = motion.phase;
    motion.step(dt, state.hovered, state.reducedMotion);
    if (state.idlePowerSaving !== false && !state.hovered) motion.phase = phase;
    for (const material of faceMaterials.values()) material.opacity = state.hovered ? 1 : 0;
    if (physicalMaterial === 'slime') {
        // Use the same native DIP cursor/frame sample that drives hover zoom.
        // DOM enter/move events can be absent on an inactive transparent window.
        const pointer = state.pointer;
        if (pointer && state.hovered && !state.interactionActive && !state.reducedMotion
            && pointer.x >= 0 && pointer.y >= 0 && pointer.x <= 1 && pointer.y <= 1) {
            contactRay.setFromCamera(new THREE.Vector2(pointer.x * 2 - 1, 1 - pointer.y * 2), camera);
            slime.setContact(pickSurfacePoint(contactRay.ray, cube.quaternion));
        } else slime.setContact(null);
        const wasActive = slime.isActive;
        slime.step(dt || 1 / 30, state.reducedMotion);
        if (wasActive || slime.isActive || state.reducedMotion) slimeShell!.update(slime.deformation);
    }
    updateGlassMaterial(glass.material, state.displayedAppearance, motion.engagement);
    pearl.material.map!.offset.x = -motion.phase;
    chroma.material.map!.offset.x = motion.phase;
    energy.material.map!.offset.x = motion.phase;
    const opacity = physicalMaterial === 'slime' ? 0.55 : 0.25;
    pearl.material.opacity = opacity * (0.55 + 0.2 * motion.engagement);
    chroma.material.opacity =
        opacity * 1.15 *
        state.displayedAppearance.glowIntensity *
        (0.55 + 0.25 * motion.engagement) *
        (0.94 + 0.06 * Math.sin(motion.phase * 2 * Math.PI));
    energy.material.opacity =
        opacity *
        state.displayedAppearance.glowIntensity *
        (state.displayedAppearance.surfaceStyle === 'moonstone' ? 0.1 : 0.2) *
        (1 - 0.86 * motion.engagement);
    renderer.render(scene, camera);
    metrics.frames++;
    dirty = false;
    const cadence = animationCadence({visible: state.visible, documentVisible: !document.hidden,
        hovered: state.hovered, interacting: state.interactionActive, reducedMotion: state.reducedMotion,
        autoRotates: state.configuration.autoRotatesWhenIdle, idlePowerSaving: state.idlePowerSaving !== false,
        slimeActive: physicalMaterial === 'slime' && slime.isActive,
        settling: Math.abs(motion.engagement - (state.hovered ? 1 : 0)) > 0.001,
        glow: state.displayedAppearance.glowIntensity});
    metrics.cadence = cadence;
    timer = cadence ? window.setTimeout(render, 1000 / cadence) : 0;
}
function requestUpdate() {
    dirty = true;
    if (!timer && snapshot?.state.visible && !document.hidden)
        timer = window.setTimeout(render, 1000 / 30);
}
export const controller = { metrics, scene, cube, camera, renderer, render, requestUpdate };
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
    document.body.dataset.hovered = String(data.state.hovered);
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

document.querySelector('#library-entry')!.addEventListener('click',()=>{void window.tcube.showLibrary().catch(console.error);});
renderer.domElement.addEventListener('pointerdown',()=>{renderer.domElement.classList.add('clicked');setTimeout(()=>renderer.domElement.classList.remove('clicked'),160);});
document.body.addEventListener('dragover',event=>{if(event.dataTransfer?.types.includes('text/plain'))event.preventDefault();});
document.body.addEventListener('drop',event=>{const text=event.dataTransfer?.getData('text/plain');if(text&&!event.dataTransfer?.files.length){event.preventDefault();void window.tcube.showLibrary(text).catch(console.error);}});
