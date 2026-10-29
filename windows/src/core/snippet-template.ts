const pattern = /\{\{([^{}\r\n]+)\}\}/g;
export function templateVariables(text: string): string[] {
    return [...new Set([...text.matchAll(pattern)].map(match => match[1]).filter(name => name.trim()))];
}
export function renderTemplate(text: string, values: Record<string, string>): string {
    return text.replace(pattern, (match, name: string) => Object.hasOwn(values, name) ? values[name] : match);
}
