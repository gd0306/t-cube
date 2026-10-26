import { build } from 'esbuild';
import { cp, mkdir, rm } from 'node:fs/promises';

await rm('dist', { recursive: true, force: true });
await mkdir('dist/renderer', { recursive: true });
await build({ entryPoints: { main: 'src/main/index.ts', preload: 'src/preload/index.ts', 'native-icons': 'src/native/icon-worker.ts' }, outdir: 'dist', outExtension: { '.js': '.cjs' }, bundle: true, platform: 'node', target: 'node22', format: 'cjs', external: ['electron', 'koffi'], sourcemap: true });
await build({ entryPoints: { widget: 'src/renderer/widget.ts', settings: 'src/renderer/settings.ts', expanded: 'src/renderer/expanded.ts' }, outdir: 'dist/renderer', bundle: true, splitting: true, platform: 'browser', target: 'chrome140', format: 'esm', sourcemap: true, minify: true });
for (const name of ['widget', 'settings', 'expanded']) {
    await cp(`src/renderer/${name}.html`, `dist/renderer/${name}.html`);
}
await cp('src/renderer', 'dist/renderer', { recursive: true, filter: name => !name.endsWith('.ts') });
await cp('assets', 'dist/assets', { recursive: true });
console.log('Built local renderer, sandboxed preload and native host.');
