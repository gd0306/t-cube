/** Matches the macOS content-library.json format. */
export interface SnippetField { id: string; label: string; value: string }
export interface TextSnippet { id: string; title: string; group: string; body: string; fields: SnippetField[]; isFavorite: boolean; isTemplate?: boolean }
export interface SnippetLibrary { version: 1; items: TextSnippet[] }
export interface ProductivityBridge {
    showLibrary(text?: string): Promise<void>;
    getLibrary(): Promise<SnippetLibrary>;
    saveSnippet(snippet: TextSnippet): Promise<SnippetLibrary>;
    deleteSnippet(id: string): Promise<SnippetLibrary>;
    moveSnippet(request: { id: string; neighborId: string }): Promise<SnippetLibrary>;
    useSnippetText(request: { text: string; paste: boolean }): Promise<{ status: string }>;
    captureClipboard(): Promise<string>;
    onLibraryCapture(callback: (text: string) => void): () => void;
    onLibraryChanged(callback: () => void): () => void;
}
