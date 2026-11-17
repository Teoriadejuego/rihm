import { validateManifest, validateResults, ContractError } from './contract.js';

export class IntegrityError extends Error { constructor(message) { super(message); this.name = 'IntegrityError'; } }
export async function sha256(bytes, cryptoProvider = globalThis.crypto) {
  const hash = await cryptoProvider.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(hash)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export function createSnapshotReader({ fetcher = globalThis.fetch, baseUrl = globalThis.document?.baseURI, timeoutMs = 12000, maxAttempts = 3, cryptoProvider = globalThis.crypto } = {}) {
  const root = new URL('.', baseUrl);
  async function request(path) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetcher(new URL(path, root), { cache: 'no-store', credentials: 'omit', redirect: 'error', signal: controller.signal });
      if (!response.ok) throw new Error(`The published data returned HTTP ${response.status}.`);
      const bytes = await response.arrayBuffer();
      if (bytes.byteLength > 8 * 1024 * 1024) throw new ContractError('The aggregate file exceeds the supported size.');
      return bytes;
    } finally { clearTimeout(timeout); }
  }
  function decode(bytes) {
    try { return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)); }
    catch { throw new ContractError('The publication contains invalid JSON.'); }
  }
  return async function read(previous = null) {
    for (let attempt = 0; attempt < Math.max(1, Math.min(maxAttempts, 3)); attempt += 1) {
      try {
        const manifest = validateManifest(decode(await request('data/public_manifest.json')));
        if (previous && manifest.publication_id === previous.manifest.publication_id && manifest.schema_version === previous.manifest.schema_version) {
          if (manifest.results_sha256 !== previous.manifest.results_sha256 || manifest.generated_at_utc !== previous.manifest.generated_at_utc) {
            throw new IntegrityError('An existing publication changed unexpectedly.');
          }
          return previous;
        }
        const bytes = await request(`data/public_results.json?publication=${encodeURIComponent(manifest.publication_id)}`);
        if (manifest.results_sha256 && await sha256(bytes, cryptoProvider) !== manifest.results_sha256) throw new IntegrityError('The publication is still updating.');
        const data = validateResults(decode(bytes));
        for (const key of ['schema_version', 'publication_id', 'generated_at_utc']) {
          if (data.metadata[key] !== manifest[key]) throw new IntegrityError('The publication files do not yet match.');
        }
        return { data, manifest };
      } catch (error) {
        if (!(error instanceof IntegrityError) || attempt >= Math.min(maxAttempts, 3) - 1) throw error;
      }
    }
  };
}

// Only one check can run at once; a failed refresh never replaces the last
// verified object. The view consumes this object as a single publication.
export function createSnapshotStore({ read, onChange = () => {}, now = () => new Date() }) {
  let current = null;
  let pending = null;
  let checkedAt = null;
  let error = null;
  const emit = (checking) => onChange({ snapshot: current, checking, checkedAt, error });
  return {
    get current() { return current; },
    check() {
      if (pending) return pending;
      error = null;
      emit(true);
      pending = Promise.resolve().then(() => read(current)).then((candidate) => {
        current = candidate;
        checkedAt = now();
      }).catch((failure) => { error = failure instanceof Error ? failure.message : 'The latest publication could not be checked.'; })
        .finally(() => { pending = null; emit(false); });
      return pending;
    }
  };
}

export function startRefresh(store, { document = globalThis.document, intervalMs = 60000, setIntervalFn = globalThis.setInterval, clearIntervalFn = globalThis.clearInterval } = {}) {
  const checkVisible = () => { if (document.visibilityState === 'visible') void store.check(); };
  const timer = setIntervalFn(checkVisible, intervalMs);
  document.addEventListener('visibilitychange', checkVisible);
  checkVisible();
  return () => { clearIntervalFn(timer); document.removeEventListener('visibilitychange', checkVisible); };
}
