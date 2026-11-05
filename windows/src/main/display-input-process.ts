import { fork } from 'node:child_process';
import { writeFileSync, mkdtempSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import type { InputJob, InputResult, InputFailureKind } from '../native/display-input';
/** A dedicated process owns every native handle. A deadline kills that process, allowing the OS to reclaim handles. */
export function runDisplayInputProcess(workerPath: string, job: InputJob, timeoutMs = 15000, execPath = process.execPath): { result: Promise<InputResult>; cancel(): void } {
    const controlDir = mkdtempSync(path.join(tmpdir(), 'tcube-input-'));
    const cancelFile = path.join(controlDir, 'cancel');
    const writeMarker = path.join(controlDir, 'write-started');
    const argument = Buffer.from(JSON.stringify({ job, cancelFile, writeMarker })).toString('base64url');
    let child: ReturnType<typeof fork> | undefined;
    let timedOut = false;
    const result = new Promise<InputResult>((resolve, reject) => {
        let response: { result?: InputResult; error?: { kind: InputFailureKind; message: string } } | undefined;
        let spawnError: Error | undefined;
        try {
            child = fork(workerPath, [argument], { execPath, env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' }, execArgv: [], stdio: ['ignore', 'ignore', 'ignore', 'ipc'], windowsHide: true });
        } catch (error) { rmSync(controlDir, { recursive: true, force: true }); reject(error); return; }
        const deadline = setTimeout(() => { timedOut = true; child?.kill(); }, timeoutMs);
        child.on('message', value => { response = value as typeof response; });
        child.on('error', error => { spawnError = error; });
        child.on('close', code => {
            clearTimeout(deadline);
            let writeStarted = false;
            try { statSync(writeMarker); writeStarted = true; }
            catch (error) { if ((error as NodeJS.ErrnoException).code !== 'ENOENT') writeStarted = true; }
            try { rmSync(controlDir, { recursive: true, force: true }); } catch {}
            const interrupted = timedOut || !!spawnError || code !== 0;
            if (interrupted) {
                if (job.kind === 'switch' && writeStarted) resolve({ status: 'sent-unconfirmed' });
                else if (timedOut) reject(new Error('读取显示器超时，未开始切换。请检查连接。'));
                else reject(spawnError ?? new Error(`显示器进程退出 (${code})`));
            } else if (response?.result) resolve(response.result);
            else if (response?.error && (response.error.kind === 'not-attempted' || response.error.kind === 'write-rejected')) reject(new Error(response.error.message));
            else if (job.kind === 'switch' && writeStarted) resolve({ status: 'sent-unconfirmed' });
            else reject(new Error(response?.error?.message || `显示器进程退出 (${code})`));
        });
    });
    return { result, cancel: () => { try { writeFileSync(cancelFile, '', { flag: 'w', mode: 0o600 }); } catch { timedOut = true; child?.kill(); } } };
}
