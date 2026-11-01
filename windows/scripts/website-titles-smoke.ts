import assert from 'node:assert/strict';
import type { Page } from 'playwright';
import { FACES, type Configuration } from '../src/shared/contracts.js';

export const websiteTitle = '团队文档与项目资料入口 — Website documentation and project resources';
export function websiteTitleFixture(configuration: Configuration): Configuration {
    const fixture = structuredClone(configuration);
    fixture.autoRotatesWhenIdle = false;
    fixture.expandsFacesOnClick = true;
    for (const face of FACES) fixture.groups[face].slots = [
        { id: `${face}-website-title`, kind: 'website', name: websiteTitle, path: 'https://example.invalid/never-open' },
        { id: `${face}-ordinary-app`, kind: 'application', name: 'Ordinary application', path: 'C:\\Fixture\\NeverOpen.exe' },
        { id: `${face}-ordinary-folder`, kind: 'folder', name: 'Ordinary folder', path: 'C:\\Fixture' },
        { id: `${face}-ordinary-settings`, kind: 'systemSettings', name: 'Ordinary settings', path: 'ms-settings:display' },
    ];
    return fixture;
}

export async function assertExpandedWebsiteTitles(expanded: Page): Promise<void> {
    await expanded.locator('button').first().getByText(websiteTitle, { exact: true }).waitFor();
    const labels = await expanded.locator('button').evaluateAll(buttons => buttons.map(button => ({
        text: button.textContent?.trim(), title: button.getAttribute('title'), accessible: button.getAttribute('aria-label'),
        caption: (() => { const label = button.querySelector<HTMLElement>('.website-title');
            return label ? { overflow: getComputedStyle(label).textOverflow, nowrap: getComputedStyle(label).whiteSpace,
                clipped: label.scrollWidth > label.clientWidth } : null; })(),
    })));
    assert.equal(labels[0].text, websiteTitle);
    assert.equal(labels[0].title, websiteTitle);
    assert.equal(labels[0].accessible, websiteTitle);
    assert.deepEqual(labels[0].caption, { overflow: 'ellipsis', nowrap: 'nowrap', clipped: true });
    assert.deepEqual(labels.slice(1).map(label => label.text), ['', '', '']);
}

/** Project a visible caption from the actual curved decal and presented cube pose. */
export async function projectedWebsiteTitle(widget: Page): Promise<{ x: number; y: number }> {
    return widget.evaluate(async () => {
        const { controller } = await import(new URL('widget.js', location.href).href);
        controller.cube.updateMatrixWorld(true);
        const candidates = controller.cube.children
            .filter((mesh: any) => mesh.geometry?.getAttribute('position').count === 1089)
            .map((mesh: any) => {
                const uv = mesh.geometry.getAttribute('uv');
                let closest = 0, distance = Infinity;
                for (let i = 0; i < uv.count; i++) {
                    const d = (uv.getX(i) - 283 / 1024) ** 2 + (uv.getY(i) - (1 - 495 / 1024)) ** 2;
                    if (d < distance) { closest = i; distance = d; }
                }
                const point = controller.camera.position.clone().fromBufferAttribute(mesh.geometry.getAttribute('position'), closest)
                    .applyMatrix4(controller.cube.matrixWorld);
                const normal = controller.camera.position.clone().fromBufferAttribute(mesh.geometry.getAttribute('normal'), closest)
                    .transformDirection(controller.cube.matrixWorld);
                const score = normal.dot(controller.camera.position.clone().sub(point).normalize());
                point.project(controller.camera);
                return { x: (point.x + 1) * innerWidth / 2, y: (1 - point.y) * innerHeight / 2, score };
            }).filter((point: any) => point.score > 0 && point.x > 0 && point.x < innerWidth && point.y > 0 && point.y < innerHeight)
            .sort((a: any, b: any) => b.score - a.score);
        if (!candidates.length) throw new Error('No visible website caption in the presented cube pose');
        return { x: candidates[0].x, y: candidates[0].y };
    });
}

/** Run only inside the caller's owned, isolated Electron smoke application. Never activate a URL. */
export async function verifyWebsiteTitlesSmoke(widget: Page, settings: Page, openExpanded: () => Promise<Page>, capture: (page: Page, name: string) => Promise<void>, verifyNativeHover?: () => Promise<void>): Promise<string[]> {
    const original = await widget.evaluate(() => window.tcube.getSnapshot());
    try {
        await settings.evaluate(async ({ name, faces, groups }) => {
            for (const face of faces) {
                await window.tcube.addURLTarget({ face, slot: 0, kind: 'website', name, url: 'https://example.invalid/never-open' });
                for (const slot of [1, 2, 3]) if (groups[face].slots[slot]?.kind === 'website')
                    await window.tcube.removeTarget({ face, slot });
            }
        }, { name: websiteTitle, faces: [...FACES], groups: original.state.configuration.groups });
        await settings.evaluate(config => window.tcube.applyConfiguration(config), { ...original.state.configuration, expandsFacesOnClick: true });
        if (verifyNativeHover) await verifyNativeHover();
        const expanded = await openExpanded();
        await assertExpandedWebsiteTitles(expanded);
        await capture(expanded, 'website-titles-expanded.png');
        await expanded.keyboard.press('Escape');
        return ['Website captions show the saved full name with single-line ellipsis, full tooltip and accessible name; ordinary targets stay icon-only. No website was opened.'];
    } finally {
        await widget.evaluate(() => window.tcube.closeExpanded());
        // Target fixtures stay in the disposable smoke profile; preference changes are restored.
        await settings.evaluate(config => window.tcube.applyConfiguration(config), original.state.configuration);
    }
}
