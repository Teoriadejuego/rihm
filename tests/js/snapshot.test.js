import { describe, it, expect, vi, afterEach } from 'vitest';
import { webcrypto } from 'node:crypto';
import { createSnapshotReader, createSnapshotStore, startRefresh, sha256 } from '../../student/src/snapshot.js';
import { fixture, emptyFixture, bundle } from './fixtures.js';
const jsonResponse = (value) => new Response(typeof value === 'string' ? value : JSON.stringify(value));
const reader = (fetcher, options = {}) => createSnapshotReader({ fetcher, baseUrl: 'https://example.test/rihm/', cryptoProvider: webcrypto, ...options });
afterEach(() => vi.useRealTimers());
describe('verified snapshot loading', () => {
  it('checks manifest first and hashes exact UTF-8 bytes under the Pages subpath', async () => {
    const b = bundle(), fetcher = vi.fn().mockResolvedValueOnce(jsonResponse(b.manifest)).mockResolvedValueOnce(jsonResponse(b.text)); const result = await reader(fetcher)();
    expect(result.data).toEqual(b.data); expect(fetcher.mock.calls.map(([url]) => url.pathname)).toEqual(['/rihm/data/public_manifest.json', '/rihm/data/public_results.json']); expect(fetcher.mock.calls[1][1]).toMatchObject({ cache: 'no-store', credentials: 'omit', redirect: 'error' });
  });
  it('does not download unchanged results again', async () => { const b = bundle(), previous = { data: b.data, manifest: b.manifest }, fetcher = vi.fn().mockResolvedValue(jsonResponse(b.manifest)); expect(await reader(fetcher)(previous)).toBe(previous); expect(fetcher).toHaveBeenCalledTimes(1); });
  it('reads legacy empty files without inventing an integrity hash', async () => { const b = bundle(emptyFixture()), fetcher = vi.fn().mockResolvedValueOnce(jsonResponse(b.manifest)).mockResolvedValueOnce(jsonResponse(b.text)); expect((await reader(fetcher)()).data.cells).toEqual([]); });
  it('retries an overlapping deployment and then accepts the matched pair', async () => { const old = bundle(), next = bundle(fixture({ id: 'demo-next' })); const fetcher = vi.fn().mockResolvedValueOnce(jsonResponse(next.manifest)).mockResolvedValueOnce(jsonResponse(old.text)).mockResolvedValueOnce(jsonResponse(next.manifest)).mockResolvedValueOnce(jsonResponse(next.text)); expect((await reader(fetcher)()).manifest.publication_id).toBe('demo-next'); expect(fetcher).toHaveBeenCalledTimes(4); });
  it('bounds retries on persistent mismatch', async () => { const b = bundle(), fetcher = vi.fn(async (url) => jsonResponse(url.pathname.endsWith('manifest.json') ? b.manifest : b.text + ' ')); await expect(reader(fetcher)()).rejects.toThrow(/updating/); expect(fetcher).toHaveBeenCalledTimes(6); });
  it('detects an identifier mismatch even with a matching byte hash', async () => { const b = bundle(); b.manifest.publication_id = 'different-id'; const fetcher = vi.fn(async (url) => jsonResponse(url.pathname.endsWith('manifest.json') ? b.manifest : b.text)); await expect(reader(fetcher)()).rejects.toThrow(/do not yet match/); });
  it('rejects mutation of an existing immutable publication', async () => { const b = bundle(), fetcher = vi.fn(async () => jsonResponse({ ...b.manifest, results_sha256: 'b'.repeat(64) })); await expect(reader(fetcher)({ data: b.data, manifest: b.manifest })).rejects.toThrow(/changed unexpectedly/); expect(fetcher).toHaveBeenCalledTimes(3); });
  it('does not retry malformed JSON or unsupported schema', async () => { const fetcher = vi.fn(async () => jsonResponse('not JSON')); await expect(reader(fetcher)()).rejects.toThrow(/invalid JSON/); expect(fetcher).toHaveBeenCalledTimes(1); });
  it('surfaces HTTP errors without contacting a second origin', async () => { const fetcher = vi.fn(async () => new Response('', { status: 503 })); await expect(reader(fetcher)()).rejects.toThrow(/503/); expect(fetcher).toHaveBeenCalledTimes(1); expect(fetcher.mock.calls[0][0].origin).toBe('https://example.test'); });
  it('aborts a request after its deadline', async () => { vi.useFakeTimers(); const fetcher = vi.fn((url, options) => new Promise((resolve, reject) => options.signal.addEventListener('abort', () => reject(new Error('Timed out'))))); const promise = reader(fetcher, { timeoutMs: 25 })(); const rejection = expect(promise).rejects.toThrow(/Timed out/); await vi.advanceTimersByTimeAsync(26); await rejection; });
  it('hashes byte differences, including final whitespace', async () => { const b = bundle(); expect(await sha256(new TextEncoder().encode(b.text), webcrypto)).toBe(b.manifest.results_sha256); expect(await sha256(new TextEncoder().encode(b.text + '\n'), webcrypto)).not.toBe(b.manifest.results_sha256); });
  it.each([undefined, '1'])('cancels an oversized stream with content-length %s before consuming it all', async (declaredLength) => {
    const b = bundle(); let chunks = 0; let cancelled = false; let signal;
    const fetcher = vi.fn(async (url, options) => {
      if (url.pathname.endsWith('manifest.json')) return jsonResponse(b.manifest);
      signal = options.signal;
      const stream = new ReadableStream({
        pull(controller) { if (chunks === 16) controller.close(); else { chunks++; controller.enqueue(new Uint8Array(1024 * 1024)); } },
        cancel() { cancelled = true; }
      }, { highWaterMark: 0 });
      return new Response(stream, { headers: declaredLength ? { 'content-length': declaredLength } : {} });
    });
    await expect(reader(fetcher)()).rejects.toThrow(/exceeds the supported size/);
    expect(chunks).toBe(9); expect(cancelled).toBe(true); expect(signal.aborted).toBe(true);
    expect(fetcher).toHaveBeenCalledTimes(2);
  });
  it('rejects an advertised oversized body before reading any chunks', async () => {
    const b = bundle(); let pulls = 0; let cancelled = false;
    const fetcher = vi.fn(async (url) => url.pathname.endsWith('manifest.json') ? jsonResponse(b.manifest) : new Response(new ReadableStream({ pull() { pulls++; }, cancel() { cancelled = true; } }, { highWaterMark: 0 }), { headers: { 'content-length': String(16 * 1024 * 1024) } }));
    await expect(reader(fetcher)()).rejects.toThrow(/exceeds the supported size/);
    expect(pulls).toBe(0); expect(cancelled).toBe(true);
  });
  it('hashes the unchanged UTF-8 bytes when a multibyte character crosses stream chunks', async () => {
    const data = fixture(); data.metadata.data_note = 'Café — synthetic data only.';
    const b = bundle(data), bytes = new TextEncoder().encode(b.text), pivot = bytes.indexOf(0xc3);
    const chunks = [bytes.slice(0, pivot + 1), bytes.slice(pivot + 1, pivot + 2), bytes.slice(pivot + 2)];
    const fetcher = vi.fn(async (url) => url.pathname.endsWith('manifest.json') ? jsonResponse(b.manifest) : new Response(new ReadableStream({ pull(controller) { const next = chunks.shift(); if (next) controller.enqueue(next); else controller.close(); } })));
    const result = await reader(fetcher)();
    expect(result.data).toEqual(data); expect(result.manifest.results_sha256).toBe(b.manifest.results_sha256);
  });
  it('accepts exactly the byte limit and preserves trailing JSON whitespace for the hash', async () => {
    const b = bundle(); const original = new TextEncoder().encode(b.text);
    const bytes = new Uint8Array(8 * 1024 * 1024); bytes.fill(32); bytes.set(original);
    b.manifest.results_sha256 = await sha256(bytes, webcrypto);
    let offset = 0;
    const fetcher = vi.fn(async (url) => url.pathname.endsWith('manifest.json') ? jsonResponse(b.manifest) : new Response(new ReadableStream({ pull(controller) { if (offset === bytes.length) controller.close(); else { controller.enqueue(bytes.slice(offset, offset + 65536)); offset += 65536; } } })));
    expect((await reader(fetcher)()).data).toEqual(b.data);
  });
});
describe('atomic refresh state', () => {
  it('coalesces concurrent checks into one operation', async () => { let release; const read = vi.fn(() => new Promise((r) => { release = r; })), store = createSnapshotStore({ read }); const a = store.check(), b = store.check(); expect(a).toBe(b); await Promise.resolve(); expect(read).toHaveBeenCalledTimes(1); release({ data: fixture(), manifest: bundle().manifest }); await a; });
  it('keeps the verified snapshot after network failure and recovers', async () => { const first = { data: fixture(), manifest: bundle().manifest }, second = { data: fixture({ id: 'next' }), manifest: bundle(fixture({ id: 'next' })).manifest }; const events = [], read = vi.fn().mockResolvedValueOnce(first).mockRejectedValueOnce(new Error('offline')).mockResolvedValueOnce(second), store = createSnapshotStore({ read, onChange: (e) => events.push(e) }); await store.check(); await store.check(); expect(store.current).toBe(first); expect(events.at(-1).error).toBe('offline'); await store.check(); expect(store.current).toBe(second); expect(events.at(-1).error).toBeNull(); });
  it('only polls while visible and checks immediately on return', () => { vi.useFakeTimers(); const doc = new EventTarget(); doc.visibilityState = 'visible'; const store = { check: vi.fn() }; const stop = startRefresh(store, { document: doc }); expect(store.check).toHaveBeenCalledTimes(1); vi.advanceTimersByTime(60000); expect(store.check).toHaveBeenCalledTimes(2); doc.visibilityState = 'hidden'; vi.advanceTimersByTime(120000); expect(store.check).toHaveBeenCalledTimes(2); doc.visibilityState = 'visible'; doc.dispatchEvent(new Event('visibilitychange')); expect(store.check).toHaveBeenCalledTimes(3); stop(); vi.advanceTimersByTime(60000); expect(store.check).toHaveBeenCalledTimes(3); });
});
