import { parentPort, workerData } from 'node:worker_threads';
import { extractShellIcon } from './win32.js';
try { parentPort?.postMessage(extractShellIcon(workerData)); }
catch { parentPort?.postMessage(null); }
