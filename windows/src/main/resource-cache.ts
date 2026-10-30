/** Bounded LRU ownership of asynchronous resources. Evicted work may finish for its caller,
 * but never re-enters the cache. Transient resources are released as soon as loading settles. */
export class AsyncResourceCache<T> {
    private readonly entries = new Map<string, Promise<T>>();
    constructor(private readonly capacity: number, private readonly retainResolved = true) {
        if (!Number.isInteger(capacity) || capacity < 1) throw new Error('Invalid resource cache capacity');
    }
    getOrLoad(key: string, load: () => Promise<T>): Promise<T> {
        const existing = this.entries.get(key);
        if (existing) {
            this.entries.delete(key);
            this.entries.set(key, existing);
            return existing;
        }
        const pending = load().then(
            value => {
                if (!this.retainResolved && this.entries.get(key) === pending) this.entries.delete(key);
                return value;
            },
            error => {
                if (this.entries.get(key) === pending) this.entries.delete(key);
                throw error;
            },
        );
        this.entries.set(key, pending);
        while (this.entries.size > this.capacity) this.entries.delete(this.entries.keys().next().value!);
        return pending;
    }
    clear(): void { this.entries.clear(); }
}
