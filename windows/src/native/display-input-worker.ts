import { existsSync, writeFileSync } from 'node:fs';
import { runDisplayInputJob, classifyInputError, InputOperationError, type InputJob } from './display-input';
import { createWindowsDisplayInputDriver } from './display-input-win32';
async function main(): Promise<void> {
    let writeMarker: string | undefined;
    try {
        const input = JSON.parse(Buffer.from(process.argv[2], 'base64url').toString('utf8')) as { job: InputJob; cancelFile: string; writeMarker: string };
        writeMarker = input.writeMarker;
        const result = await runDisplayInputJob(createWindowsDisplayInputDriver(), input.job, () => existsSync(input.cancelFile), () => writeFileSync(input.writeMarker, '', { flag: 'wx', mode: 0o600 }));
        process.send?.({ result });
    } catch (error) {
        const failure = error instanceof InputOperationError || !writeMarker || !existsSync(writeMarker)
            ? classifyInputError(error) : { kind: 'uncertain' as const, message: String(error) };
        process.send?.({ error: failure });
    } finally { process.disconnect?.(); }
}
void main();
