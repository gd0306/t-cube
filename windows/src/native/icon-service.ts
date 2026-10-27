import { Worker } from 'node:worker_threads';
import path from 'node:path';
import type { ShellBitmap } from './win32.js';

function extract(filePath: string): Promise<ShellBitmap | null> {
    if (process.platform !== 'win32') return Promise.resolve(null);
    return new Promise(resolve => {
        const worker = new Worker(path.join(__dirname, 'native-icons.cjs'), { workerData: filePath });
        let settled = false;
        const finish = (result: ShellBitmap | null) => {
            if (settled) return;
            settled = true;
            clearTimeout(timeout);
            void worker.terminate();
            resolve(result ? { ...result, pixels: Buffer.from(result.pixels) } : null);
        };
        const timeout = setTimeout(() => finish(null), 5000);
        worker.once('message', finish);
        worker.once('error', () => finish(null));
        worker.once('exit', () => finish(null));
    });
}

// Avoid creating one Node isolate per configured shortcut during startup.
const lanes: Promise<unknown>[] = [Promise.resolve(), Promise.resolve()];
let nextLane = 0;
export function extractIconInWorker(filePath: string): Promise<ShellBitmap | null> {
    if (process.platform !== 'win32') return Promise.resolve(null);
    const lane = nextLane++ % lanes.length;
    const operation = lanes[lane].then(() => extract(filePath));
    lanes[lane] = operation.catch(() => null);
    return operation;
}
