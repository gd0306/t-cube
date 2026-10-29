import assert from 'node:assert/strict';
import type { Page } from 'playwright';

/** Opt-in real WebGL regression. Call with the native cursor outside the widget. */
export async function verifyThemeTransitionSmoke(widget: Page, settings: Page): Promise<string[]> {
    const saved = (await widget.evaluate(() => window.tcube.getSnapshot())).state;
    assert.equal(saved.hovered, false, 'Theme smoke requires the native pointer outside the widget');
    assert.equal(saved.reducedMotion, false, 'Theme smoke requires native animations enabled');
    const read = () => widget.evaluate(async () => {
        const { controller } = await import(new URL('widget.js', location.href).href);
        const shell = controller.cube.getObjectByName('glass-shell');
        // Render and read in one task: the default framebuffer need not preserve its contents.
        controller.renderer.render(controller.scene, controller.camera);
        const gl = controller.renderer.getContext();
        const { width, height } = controller.renderer.domElement;
        const pixels = new Uint8Array(width * height * 4);
        gl.readPixels(0, 0, width, height, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
        const channels = [0, 0, 0, 0];
        for (let i = 0; i < pixels.length; i++) channels[i % 4] += pixels[i];
        return { ...controller.metrics, channels, primary: shell.material.uniforms.primary.value.toArray() as number[],
            maps: controller.cube.children.filter((mesh: any) => mesh.name.startsWith('optical-')).map((mesh: any) => mesh.material.map.uuid) as string[],
            geometry: controller.cube.children.map((mesh: any) => mesh.geometry?.uuid) as string[],
            pose: controller.cube.quaternion.toArray() as number[],
            runnable: controller.renderer.info.programs.every((program: any) => program.diagnostics?.runnable !== false) as boolean };
    });
    const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));
    try {
        await settings.evaluate(() => window.tcube.setPerformanceSettings(true));
        const red = structuredClone(saved.configuration);
        red.autoRotatesWhenIdle = false;
        red.themeCycle.isEnabled = false;
        red.appearance = { primaryHex: '#FF0000', secondaryHex: '#FF0000', glowIntensity: 0.7, surfaceStyle: 'aurora', material: 'glass' };
        await settings.evaluate(config => window.tcube.applyConfiguration(config), red);
        await sleep(900);
        const before = await read();
        const blue = structuredClone(red);
        blue.appearance.primaryHex = blue.appearance.secondaryHex = '#0000FF';
        await settings.evaluate(config => window.tcube.applyConfiguration(config), blue);
        const samples = [];
        for (let i = 0; i < 35; i++) { samples.push(await read()); await sleep(20); }
        const after = samples.at(-1)!;
        assert.ok(samples.some(sample => sample.primary[0] > 0.05 && sample.primary[0] < 0.95), 'Theme must render intermediate colors');
        assert.ok(samples.some(sample => sample.cadence === 30), 'Theme must wake office idle at 30Hz');
        assert.equal(after.cadence, 0, 'Completed theme must release the office animation timer');
        assert.deepEqual(after.primary, [0, 0, 1]);
        for (const sample of samples) {
            assert.ok(sample.runnable, 'Optical blend GLSL must compile on the native renderer');
            assert.deepEqual(sample.geometry, before.geometry, 'Palette transitions must retain geometry and input surfaces');
            assert.deepEqual(sample.pose, before.pose, 'Palette blending must not introduce an old/new rotation pose');
            assert.ok(Math.abs(sample.channels[3] - before.channels[3]) <= 8, 'Color-only transitions must retain alpha instead of doubling opacity');
            for (let channel = 0; channel < 3; channel++) {
                const min = Math.min(before.channels[channel], after.channels[channel]);
                const max = Math.max(before.channels[channel], after.channels[channel]);
                assert.ok(sample.channels[channel] >= min - 100 && sample.channels[channel] <= max + 100,
                    'Color-only transitions must stay within their rendered endpoint brightness');
            }
        }
        for (let layer = 0; layer < 3; layer++) assert.ok(new Set(samples.map(sample => sample.maps[layer])).size <= 2,
            'Animation frames must reuse endpoint maps');
        const idleFrames = after.frames;
        await sleep(180);
        assert.equal((await read()).frames, idleFrames, 'Office idle must stop rendering after theme completion');
        // Interrupt twice while a blend is active; final textures and palette must settle.
        await settings.evaluate(config => window.tcube.applyConfiguration(config), red);
        await sleep(100);
        await settings.evaluate(config => window.tcube.applyConfiguration(config), blue);
        await sleep(100);
        await settings.evaluate(config => window.tcube.applyConfiguration(config), red);
        await sleep(650);
        const interrupted = await read();
        assert.deepEqual(interrupted.primary, [1, 0, 0]);
        assert.equal(interrupted.cadence, 0);
        assert.ok(interrupted.runnable);
        return ['Opt-in WebGL theme regression: intermediate colors, bounded RGB/alpha, shared geometry/pose, reused maps, interrupted retargeting and idle timer release passed.'];
    } finally {
        await settings.evaluate(config => window.tcube.applyConfiguration(config), saved.configuration);
        await settings.evaluate(value => window.tcube.setPerformanceSettings(value), saved.idlePowerSaving === true);
    }
}
