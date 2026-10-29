import type { SnippetLibrary, TextSnippet } from '../shared/productivity';
import type { SnippetPersistence } from '../core/snippet-store';
import { validateSnippetId, validateSnippetLibrary } from '../core/snippet-library';
export class ContentLibraryService {
    constructor(readonly store: SnippetPersistence) {}
    get(): Promise<SnippetLibrary> { return this.store.load(); }
    reload(): Promise<SnippetLibrary> { return this.store.reload(); }
    save(snippet: TextSnippet): Promise<SnippetLibrary> {
        const validated = validateSnippetLibrary({ version: 1, items: [snippet] }).items[0];
        validated.title = validated.title.trim(); validated.group = validated.group.trim();
        return this.store.update(library => {
            const index = library.items.findIndex(item => item.id.toLowerCase() === validated.id.toLowerCase());
            if (index < 0) library.items.push(validated); else library.items[index] = validated;
        });
    }
    delete(id: string): Promise<SnippetLibrary> {
        validateSnippetId(id);
        return this.store.update(library => { library.items = library.items.filter(item => item.id.toLowerCase() !== id.toLowerCase()); });
    }
    move(request: { id: string; neighborId: string }): Promise<SnippetLibrary> {
        validateSnippetId(request.id); validateSnippetId(request.neighborId);
        return this.store.update(library => {
            const source = library.items.findIndex(item => item.id === request.id), destination = library.items.findIndex(item => item.id === request.neighborId);
            if (source < 0 || destination < 0 || source === destination || library.items[source].isFavorite !== library.items[destination].isFavorite) return;
            [library.items[source], library.items[destination]] = [library.items[destination], library.items[source]];
        });
    }
}
