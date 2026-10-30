import assert from 'node:assert/strict';
import test from 'node:test';

test('transient image resources coalesce pending work and reload after the last load settles', async () => {
    const { AsyncResourceCache } = await import('../src/main/resource-cache');
    const cache = new AsyncResourceCache<{ pixels: Buffer }>(32, false);
    let finish!: (value: { pixels: Buffer }) => void;
    const first = cache.getOrLoad('shell:Calculator', () => new Promise(resolve => { finish = resolve; }));
    const joined = cache.getOrLoad('shell:Calculator', async () => { throw Error('duplicate image extraction'); });
    const original = { pixels: Buffer.alloc(64) };
    finish(original);
    assert.equal(await first, original);
    assert.equal(await joined, original);
    const fresh = await cache.getOrLoad('shell:Calculator', async () => ({ pixels: Buffer.alloc(64) }));
    assert.notEqual(fresh, original, 'Completed native images must no longer be retained by the discovery cache');
});

test('clearing an in-flight resource prevents stale completion from replacing or evicting a refreshed load', async () => {
    const { AsyncResourceCache } = await import('../src/main/resource-cache');
    const cache = new AsyncResourceCache<string>(32, false);
    let finishOld!: (value: string) => void, finishNew!: (value: string) => void;
    const old = cache.getOrLoad('shell:Calculator', () => new Promise(resolve => { finishOld = resolve; }));
    cache.clear();
    const fresh = cache.getOrLoad('shell:Calculator', () => new Promise(resolve => { finishNew = resolve; }));
    finishOld('old pixels');
    assert.equal(await old, 'old pixels');
    const joined = cache.getOrLoad('shell:Calculator', async () => 'unexpected duplicate pixels');
    finishNew('fresh pixels');
    assert.equal(await fresh, 'fresh pixels');
    assert.equal(await joined, 'fresh pixels');
});
