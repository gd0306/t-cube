import { CLIPBOARD_HISTORY_LIMITS } from './clipboard-history';

export const CLIPBOARD_TEXT_ACTIONS = {
    original: '原文（纯文本）', trimLines: '去除每行首尾空白', collapseBlankLines: '合并连续空行',
    uppercase: '转为大写', lowercase: '转为小写', jsonPretty: 'JSON 格式化', jsonCompact: 'JSON 压缩',
    urlEncode: 'URL 编码（参数值）', urlDecode: 'URL 解码',
} as const;
export type ClipboardTextAction = keyof typeof CLIPBOARD_TEXT_ACTIONS;
const encoder = new TextEncoder();
const limit = CLIPBOARD_HISTORY_LIMITS.itemBytes;
const invalidJSON = () => new Error('JSON 格式不正确或嵌套超过 128 层；原文保持不变。');

/** Formatting preserves every non-whitespace token, including huge numbers and duplicate keys. */
function formatJSON(source: string, pretty: boolean): string {
    let index = 0, size = 0;
    const output: string[] = [];
    function emit(text: string) {
        size += encoder.encode(text).length;
        if (size > limit) throw new Error('处理结果超过 64 KiB，请减少内容；原文保持不变。');
        output.push(text);
    }
    function whitespace() { while (index < source.length && /[\t\n\r ]/.test(source[index])) index++; }
    function take(char: string): boolean { whitespace(); if (source[index] !== char) return false; index++; return true; }
    function line(depth: number) { if (pretty) emit('\n' + '  '.repeat(depth)); }
    function string() {
        if (source[index] !== '"') throw invalidJSON();
        const start = index++;
        while (index < source.length) {
            const char = source[index++];
            if (char === '"') { emit(source.slice(start, index)); return; }
            if (char.charCodeAt(0) < 32) throw invalidJSON();
            if (char === '\\') {
                const escape = source[index++];
                if (escape === 'u') {
                    if (!/^[0-9a-fA-F]{4}$/.test(source.slice(index, index + 4))) throw invalidJSON();
                    index += 4;
                } else if (!escape || !'"/\\bfnrt'.includes(escape)) throw invalidJSON();
            }
        }
        throw invalidJSON();
    }
    function value(depth: number) {
        whitespace();
        if (depth > 128 || index >= source.length) throw invalidJSON();
        const char = source[index];
        if (char === '{' || char === '[') {
            const object = char === '{', close = object ? '}' : ']';
            index++; emit(char);
            if (take(close)) { emit(close); return; }
            line(depth + 1);
            while (true) {
                if (object) { whitespace(); string(); if (!take(':')) throw invalidJSON(); emit(pretty ? ': ' : ':'); }
                value(depth + 1);
                if (take(close)) { line(depth); emit(close); return; }
                if (!take(',')) throw invalidJSON();
                emit(','); line(depth + 1);
            }
        } else if (char === '"') string();
        else {
            const start = index;
            while (index < source.length && !/[\t\n\r ,\]}]/.test(source[index])) index++;
            const token = source.slice(start, index);
            if (!/^(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)$/.test(token)) throw invalidJSON();
            emit(token);
        }
    }
    value(0); whitespace();
    if (index !== source.length) throw invalidJSON();
    return output.join('');
}

export function processClipboardText(source: string, action: ClipboardTextAction): string {
    if (!source.trim() || source.includes('\0') || encoder.encode(source).length > limit) throw new Error('文字为空、含空字符或超过 64 KiB。');
    let result: string;
    const lines = () => source.replace(/\r\n?/g, '\n').split('\n');
    switch (action) {
        case 'original': result = source; break;
        case 'trimLines': result = lines().map(line => line.trim()).join('\n'); break;
        case 'collapseBlankLines': {
            let previousBlank = false;
            result = lines().filter(line => { const blank = !line.trim(), keep = !blank || !previousBlank; previousBlank = blank; return keep; }).join('\n'); break;
        }
        case 'uppercase': result = source.toUpperCase(); break;
        case 'lowercase': result = source.toLowerCase(); break;
        case 'jsonPretty': case 'jsonCompact': result = formatJSON(source, action === 'jsonPretty'); break;
        case 'urlEncode': case 'urlDecode':
            try { result = action === 'urlEncode' ? encodeURIComponent(source).replace(/[!'()*]/g, char => '%' + char.charCodeAt(0).toString(16).toUpperCase()) : decodeURIComponent(source); }
            catch { throw new Error('URL 编码不完整或不是有效的 UTF-8；原文保持不变。'); }
            break;
        default: throw new Error('未知的文字处理操作。');
    }
    if (encoder.encode(result).length > limit) throw new Error('处理结果超过 64 KiB，请减少内容；原文保持不变。');
    if (!result.trim() || result.includes('\0')) throw new Error('处理结果为空或含空字符；原文保持不变。');
    return result;
}

export function clipboardTextNotice(source: string, action: ClipboardTextAction, result: string): string | undefined {
    if (action === 'original') return;
    if (source === result) {
        if (action === 'urlEncode') return '内容不含需要转义的字符，无需 URL 编码。';
        if (action === 'urlDecode') return '原内容没有需要解码的百分号编码，内容保持原样。';
        if (action === 'jsonPretty' || action === 'jsonCompact') return '内容已符合所选 JSON 格式，无需修改。';
        return '处理结果与原文相同，无需修改。';
    }
    if (action === 'urlEncode' && /%[0-9a-fA-F]{2}/.test(source)) return '内容含 %XX 序列，再编码会将 % 编为 %25，请确认预览。';
}
