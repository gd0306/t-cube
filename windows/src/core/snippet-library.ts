import type { SnippetLibrary, TextSnippet } from '../shared/productivity';
export const SNIPPET_LIMITS = { items: 2000, fields: 64, title: 256, group: 256, label: 256, text: 262144, payload: 8 * 1024 * 1024 } as const;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function validateSnippetId(value: unknown): asserts value is string {
    if (typeof value !== 'string' || !uuid.test(value)) throw new Error('内容标识无效。');
}
function record(value: unknown): asserts value is Record<string, unknown> {
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('内容库格式无效。');
}
function text(value: unknown, max: number): asserts value is string {
    if (typeof value !== 'string' || value.length > max || value.includes('\0')) throw new Error('内容文本无效或过长。');
}
export function validateSnippetText(value: unknown): asserts value is string { text(value, SNIPPET_LIMITS.text); }
export function validateSnippetLibrary(value: unknown): SnippetLibrary {
    record(value);
    if (value.version !== 1 || !Array.isArray(value.items) || value.items.length > SNIPPET_LIMITS.items) throw new Error('内容库版本或数量无效。');
    const ids = new Set<string>(), fieldIds = new Set<string>();
    for (const item of value.items) {
        record(item); validateSnippetId(item.id);
        if (ids.has(item.id.toLowerCase())) throw new Error('内容标识重复。');
        ids.add(item.id.toLowerCase());
        text(item.title, SNIPPET_LIMITS.title); text(item.group, SNIPPET_LIMITS.group); text(item.body, SNIPPET_LIMITS.text);
        if ((item.isTemplate !== undefined && typeof item.isTemplate !== 'boolean') || !item.title.trim() || typeof item.isFavorite !== 'boolean' || !Array.isArray(item.fields) || item.fields.length > SNIPPET_LIMITS.fields) throw new Error('请填写标题，并检查字段格式。');
        let hasContent = Boolean(item.body.trim());
        for (const field of item.fields) {
            record(field); validateSnippetId(field.id);
            if (fieldIds.has(field.id.toLowerCase())) throw new Error('字段标识重复。');
            fieldIds.add(field.id.toLowerCase()); text(field.label, SNIPPET_LIMITS.label); text(field.value, SNIPPET_LIMITS.text);
            if (field.value.trim() && !field.label.trim()) throw new Error('有值的字段需要填写名称。');
            hasContent ||= Boolean(field.value.trim());
        }
        if (!hasContent) throw new Error('请填写正文或至少一个字段的值。');
        if (fullSnippetText(item as unknown as TextSnippet).length > SNIPPET_LIMITS.text) throw new Error('单条内容过长，请拆分保存。');
    }
    if (new TextEncoder().encode(JSON.stringify(value, null, 4)).byteLength > SNIPPET_LIMITS.payload) throw new Error('内容库文件过大。');
    return structuredClone(value) as unknown as SnippetLibrary;
}
export function fullSnippetText(snippet: TextSnippet): string {
    return [...(snippet.body.trim() ? [snippet.body] : []), ...snippet.fields.filter(field => field.value.trim()).map(field => `${field.label}：${field.value}`)].join('\n');
}
function searchable(value: string): string { return value.normalize('NFD').replace(/\p{M}/gu, '').toLocaleLowerCase(); }
export function filteredSnippets(library: SnippetLibrary, options: { query?: string; group?: string; favoritesOnly?: boolean } = {}): TextSnippet[] {
    const query = searchable(options.query?.trim() ?? '');
    const matches = library.items.filter(item => (options.group === undefined || item.group === options.group) && (!options.favoritesOnly || item.isFavorite)
        && (!query || [item.title, item.group, item.body, ...item.fields.flatMap(field => [field.label, field.value])].some(value => searchable(value).includes(query))));
    return [...matches.filter(item => item.isFavorite), ...matches.filter(item => !item.isFavorite)];
}
