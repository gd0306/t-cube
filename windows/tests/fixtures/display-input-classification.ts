// Test-only child: exercise the production job and error classifier without hardware.
import { writeFileSync } from 'node:fs';
import { classifyInputError, runDisplayInputJob, type DisplayInputDriver, type InputJob } from '../../src/native/display-input';
const input = JSON.parse(Buffer.from(process.argv[2], 'base64url').toString('utf8')) as { job: InputJob; writeMarker: string };
if (input.job.kind !== 'switch' || !input.job.mapping) throw new Error('Missing fixture mapping');
const mode = input.job.mapping.typeC; let writes = 0, checks = 0;
const driver: DisplayInputDriver<number> = {
    enumerate: () => [{ identity: input.job.kind === 'switch' ? input.job.identity : '', name: '', handles: [1] }],
    read: () => ({ current: 5, maximum: 14 }),
    write: () => { writes++; if (mode === 12) throw new Error('native exception'); return false; },
    destroy: () => {}, delay: () => {}
};
void runDisplayInputJob(driver, input.job, () => mode === 11 && ++checks === 2, () => writeFileSync(input.writeMarker, '', { flag: 'wx' }))
    .then(result => process.send?.({ result }), error => { const failure = classifyInputError(error); process.send?.({ error: { ...failure, message: `${failure.message} (writes=${writes})` } }); })
    .finally(() => process.disconnect?.());
