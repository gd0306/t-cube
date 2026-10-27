import type { Snapshot } from '../shared/contracts';

export function padTransparentRGB(
    pixels: Uint8ClampedArray,
    width: number,
    height: number,
    radius = 16,
): void {
    const distance = new Uint8Array(width * height).fill(255),
        queue: number[] = [];
    for (let i = 0; i < width * height; i++) {
        if (!pixels[i * 4 + 3]) continue;
        distance[i] = 0;
        const x = i % width,
            y = Math.floor(i / width);
        if (
            (x > 0 && !pixels[(i - 1) * 4 + 3]) ||
            (x + 1 < width && !pixels[(i + 1) * 4 + 3]) ||
            (y > 0 && !pixels[(i - width) * 4 + 3]) ||
            (y + 1 < height && !pixels[(i + width) * 4 + 3])
        )
            queue.push(i);
    }
    for (let head = 0; head < queue.length; head++) {
        const i = queue[head],
            x = i % width,
            y = Math.floor(i / width);
        if (distance[i] >= radius) continue;
        for (const n of [
            x > 0 ? i - 1 : -1,
            x + 1 < width ? i + 1 : -1,
            y > 0 ? i - width : -1,
            y + 1 < height ? i + width : -1,
        ]) {
            if (n < 0 || distance[n] !== 255) continue;
            distance[n] = distance[i] + 1;
            for (let c = 0; c < 3; c++) pixels[n * 4 + c] = pixels[i * 4 + c];
            queue.push(n);
        }
    }
}
export function wheelDelta(x: number, y: number, shift: boolean, mode: number) {
    if (shift && x === 0) {
        x = y;
        y = 0;
    }
    return { dx: x ? -x : 0, dy: y ? -y : 0, precise: mode === 0 };
}
export function subscribe(update: (snapshot: Snapshot) => void): void {
    let state: Snapshot['state'] | undefined, icons: Snapshot['icons'] | undefined;
    let stateReceived = false,
        iconsReceived = false;
    const emit = () => {
        if (state && icons) update({ state, icons });
    };
    window.tcube.onState((value) => {
        stateReceived = true;
        state = value;
        emit();
    });
    window.tcube.onIcons((value) => {
        iconsReceived = true;
        icons = value;
        emit();
    });
    window.tcube
        .getSnapshot()
        .then((snapshot) => {
            if (!stateReceived) state = snapshot.state;
            if (!iconsReceived) icons = snapshot.icons;
            emit();
        })
        .catch((error) => console.error(error));
}
