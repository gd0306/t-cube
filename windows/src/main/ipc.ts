import { normalizeConfiguration } from '../core/configuration';
import { FACES } from '../shared/contracts';
import type { Configuration, Face, Hit, Placement, TargetRequest } from '../shared/contracts';
import type { LauncherHost } from './application';
import type { InstalledApplications } from './applications';

export const CHANNELS = {
    getSnapshot: 'tcube:snapshot', state: 'tcube:state', icons: 'tcube:icons', error: 'tcube:error',
    beginPointer: 'tcube:pointer-begin', endPointer: 'tcube:pointer-end', applyConfiguration: 'tcube:configure',
    chooseTarget: 'tcube:choose', dropTargets: 'tcube:drop', removeTarget: 'tcube:remove', moveTarget: 'tcube:move',
    renameGroup: 'tcube:rename', launch: 'tcube:launch', place: 'tcube:place', showSettings: 'tcube:settings',
    quit: 'tcube:quit', closeExpanded: 'tcube:close-expanded',
    listApplications: 'tcube:applications', applicationIcons: 'tcube:application-icons', addApplication: 'tcube:add-application'
} as const;
export type WindowRole = 'widget' | 'settings' | 'expanded';
interface Sender { id: number; mainFrame: unknown }
interface Event { sender: Sender; senderFrame: unknown }
interface IPCRegistrar { handle(channel: string, handler: (event: Event, payload?: unknown) => Promise<unknown>): void }
const invalid = (): never => { throw new Error('Invalid request'); };
const record = (value: unknown): Record<string, unknown> => value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : invalid();
function face(value: unknown): Face { return FACES.includes(value as Face) ? value as Face : invalid(); }
function slot(value: unknown): number { return typeof value === 'number' && Number.isInteger(value) && value >= 0 && value < 4 ? value : invalid(); }
function text(value: unknown, max: number): string { return typeof value === 'string' && value.trim().length > 0 && value.length <= max ? value : invalid(); }
function target(value: unknown): { face: Face; slot: number } { const request = record(value); return { face: face(request.face), slot: slot(request.slot) }; }
function hit(value: unknown): Hit | null { if (value === null) return null; const request = record(value); return { face: face(request.face), slot: request.slot === null ? null : slot(request.slot) }; }
function button(value: unknown): 0 | 2 { return value === 0 || value === 2 ? value : invalid(); }

/** Authorization runs before parsing and before touching any privileged host operation. */
export function registerIPC(ipc: IPCRegistrar, host: LauncherHost, roleForSender: (sender: Sender) => WindowRole | null, applications?: InstalledApplications): void {
    const handle = (name: string, roles: WindowRole[], operation: (value: unknown) => unknown) => {
        ipc.handle(name, async (event, value) => {
            const role = roleForSender(event.sender);
            if (!role || !roles.includes(role) || event.senderFrame !== event.sender.mainFrame) throw new Error('Not authorized');
            try { return await operation(value); }
            catch (error) { host.reportError(error); throw error; }
        });
    };
    handle(CHANNELS.getSnapshot, ['widget', 'settings', 'expanded'], () => host.snapshot);
    const catalog = () => { if (!applications) throw new Error('应用列表不可用'); return applications; };
    handle(CHANNELS.listApplications, ['settings'], value => {
        if (value !== undefined && typeof value !== 'boolean') invalid();
        return catalog().list(value as boolean | undefined);
    });
    handle(CHANNELS.applicationIcons, ['settings'], value => {
        if (!Array.isArray(value) || value.length > 32) invalid();
        return catalog().icons((value as unknown[]).map(id => text(id, 64)));
    });
    handle(CHANNELS.addApplication, ['settings'], async value => {
        const request = record(value), destination = target(value);
        const item = await catalog().materialize(text(request.applicationId, 64));
        return host.addApplication(destination, item);
    });
    handle(CHANNELS.beginPointer, ['widget'], value => host.beginPointer(button(value)));
    handle(CHANNELS.endPointer, ['widget'], value => {
        const request = record(value);
        if (!Number.isSafeInteger(request.gestureId) || (request.gestureId as number) < 1) invalid();
        if (request.cancelled !== undefined && typeof request.cancelled !== 'boolean') invalid();
        return host.endPointer({ gestureId: request.gestureId as number, button: button(request.button), hit: hit(request.hit), cancelled: request.cancelled as boolean | undefined });
    });
    handle(CHANNELS.applyConfiguration, ['settings'], value => {
        // Bound the entire JSON request before the core walks nested structures.
        if (JSON.stringify(value)?.length > 131072) invalid();
        return host.applyConfiguration(normalizeConfiguration(value) as Configuration);
    });
    handle(CHANNELS.chooseTarget, ['settings'], value => {
        const request = record(value);
        if (request.kind !== 'application' && request.kind !== 'folder') invalid();
        return host.chooseTarget({ ...target(value), kind: request.kind } as TargetRequest);
    });
    handle(CHANNELS.dropTargets, ['settings'], value => {
        const request = record(value);
        if (!Array.isArray(request.paths) || request.paths.length < 1 || request.paths.length > 4) invalid();
        const paths = (request.paths as unknown[]).map(value => text(value, 32767));
        return host.dropTargets({ paths, face: face(request.face), slot: request.slot === undefined ? undefined : slot(request.slot) });
    });
    handle(CHANNELS.removeTarget, ['settings'], value => host.removeTarget(target(value)));
    handle(CHANNELS.moveTarget, ['settings'], value => { const request = record(value); return host.moveTarget({ face: face(request.face), source: slot(request.source), destination: slot(request.destination) }); });
    handle(CHANNELS.renameGroup, ['settings'], value => { const request = record(value); return host.renameGroup({ face: face(request.face), name: text(request.name, 120) }); });
    handle(CHANNELS.launch, ['expanded'], value => host.launch(target(value)));
    handle(CHANNELS.place, ['settings'], value => {
        if (!['topLeft', 'topRight', 'bottomLeft', 'bottomRight', 'center'].includes(value as string)) invalid();
        return host.place(value as Placement);
    });
    handle(CHANNELS.showSettings, ['widget', 'settings', 'expanded'], () => host.showSettings());
    handle(CHANNELS.quit, ['settings'], () => host.quit());
    handle(CHANNELS.closeExpanded, ['widget', 'expanded'], () => host.closeExpanded());
}
