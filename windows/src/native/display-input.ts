import { normalizeIdentity, validMapping, type DisplayInputMapping } from '../shared/display-input';
export type InputFailureKind = 'not-attempted' | 'write-rejected' | 'uncertain';
export class InputOperationError extends Error {
    constructor(readonly kind: InputFailureKind, message: string, options?: ErrorOptions) { super(message, options); }
}
export function classifyInputError(error: unknown): { kind: InputFailureKind; message: string } {
    return error instanceof InputOperationError ? { kind: error.kind, message: error.message } : { kind: 'not-attempted', message: String(error) };
}
export interface InputReading { current: number; maximum: number }
export interface PhysicalGroup<H> { identity: string; name: string; handles: H[] }
export interface DisplayInputDriver<H> {
    enumerate(): PhysicalGroup<H>[];
    read(handle: H): InputReading | null;
    write(handle: H, value: number): boolean;
    destroy(handle: H): void;
    delay(): Promise<void> | void;
}
export type InputJob = { kind: 'list' } | { kind: 'switch'; identity: string; mapping?: DisplayInputMapping; target: 'typeC' | 'hdmi' };
export interface InputDisplay { identity: string; name: string; reading: InputReading | null; unavailable?: 'identity' | 'transport' | 'ddc' }
export type InputResult = { status: 'listed'; displays: InputDisplay[] } | { status: 'no-op' | 'confirmed' | 'not-applied'; reading: InputReading } | { status: 'sent-unconfirmed' };
function validReading(reading: InputReading | null): reading is InputReading {
    // Input Select is non-continuous: Win32 explicitly leaves maximum undefined.
    return reading !== null && Number.isInteger(reading.current) && reading.current >= 0 && reading.current <= 65535;
}
/** Each acquired handle is destroyed even when a read, write, or validation fails. */
export async function runDisplayInputJob<H>(driver: DisplayInputDriver<H>, job: InputJob, cancelled: () => boolean = () => false, beforeWrite: () => void = () => {}): Promise<InputResult> {
    const groups = driver.enumerate();
    let accepted = false; let phase: InputFailureKind = 'not-attempted'; let operationFailed = false;
    try {
        const identities = groups.map(group => { try { return normalizeIdentity(group.identity); } catch { return null; } });
        if (job.kind === 'list') return { status: 'listed', displays: groups.map((group, index): InputDisplay => {
            const identity = identities[index];
            const display: InputDisplay = { identity: identity ?? '', name: group.name, reading: null };
            if (!identity || identities.filter(candidate => candidate === identity).length !== 1 || group.handles.length > 1) return { ...display, unavailable: 'identity' };
            if (group.handles.length === 0) return { ...display, unavailable: 'transport' };
            try {
                const reading = driver.read(group.handles[0]);
                return validReading(reading) ? { ...display, reading } : { ...display, unavailable: 'ddc' };
            } catch { return { ...display, unavailable: 'ddc' }; }
        }) };
        const identity = normalizeIdentity(job.identity);
        if (job.target !== 'typeC' && job.target !== 'hdmi') throw new Error('Invalid input target');
        const indexes = identities.flatMap((candidate, index) => candidate === identity ? [index] : []);
        if (indexes.length !== 1 || groups[indexes[0]].handles.length !== 1) throw new Error('Display identity is ambiguous or unavailable');
        const group = groups[indexes[0]];
        const mapping = job.mapping;
        if (!validMapping(mapping)) throw new Error('Configure this display before switching');
        const handle = group.handles[0]; const before = driver.read(handle);
        if (!validReading(before) || !Object.values(mapping).includes(before.current)) throw new Error('Current source is unavailable or not calibrated');
        const target = mapping[job.target];
        if (before.current === target) return { status: 'no-op', reading: before };
        if (cancelled()) throw new Error('Display input operation cancelled');
        beforeWrite();
        if (cancelled()) throw new Error('Display input operation cancelled');
        phase = 'uncertain';
        if (!driver.write(handle, target)) throw new InputOperationError('write-rejected', 'Display input command failed');
        accepted = true;
        try { await driver.delay(); } catch { return { status: 'sent-unconfirmed' }; }
        let after: InputReading | null;
        try { after = driver.read(handle); } catch { after = null; }
        if (!validReading(after)) return { status: 'sent-unconfirmed' };
        if (after.current === target) return { status: 'confirmed', reading: after };
        if (after.current === before.current) return { status: 'not-applied', reading: after };
        return { status: 'sent-unconfirmed' };
    } catch (error) {
        operationFailed = true;
        if (error instanceof InputOperationError) throw error;
        throw new InputOperationError(phase, String(error), { cause: error });
    } finally {
        let failure: unknown;
        for (const group of groups) for (const handle of group.handles) try { driver.destroy(handle); } catch (error) { failure ??= error; }
        if (failure && !accepted && !operationFailed) throw new InputOperationError(phase, String(failure), { cause: failure });
    }
}
