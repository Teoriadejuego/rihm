export const SOCIAL = ['altruist', 'egalitarian', 'selfish', 'antisocial'];
export const LABELS = { altruist: 'Altruist', egalitarian: 'Egalitarian', selfish: 'Selfish', antisocial: 'Antisocial', inconsistent: 'Inconsistent' };
const versions = new Set(['1.0.0', '2.0.0']);
const hex = /^[a-f0-9]{64}$/;
const stamp = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/;
const object = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const text = (v) => typeof v === 'string' && v.length > 0 && v.length <= 1200 && !/[\u0000-\u001f]/.test(v);
const time = (v) => typeof v === 'string' && stamp.test(v) && Number.isFinite(Date.parse(v));
const integer = (v) => Number.isSafeInteger(v) && v >= 0;
const nullableInteger = (v) => v === null || integer(v);
const assert = (condition, message) => { if (!condition) throw new ContractError(message); };
const allowed = (value, names) => Object.keys(value).every((key) => names.includes(key));

// Match the producer's round(100 * count / denominator, 1): choose the
// nearest represented decimal neighbour, with ties to the even digit.
// Comparing distances also preserves R's behaviour just below decimal ties
// (for example the binary representation of 100 * 43 / 2000 is below 2.15).
function producerPercentage(count, denominator) {
  const value = 100 * count / denominator;
  const digit = Math.floor(value * 10);
  const lower = digit / 10;
  const upper = (digit + 1) / 10;
  const below = value - lower;
  const above = upper - value;
  return above < below || (above === below && digit % 2 === 1) ? upper : lower;
}

export class ContractError extends Error { constructor(message) { super(message); this.name = 'ContractError'; } }

export function validateManifest(value) {
  assert(object(value), 'Invalid publication manifest.');
  assert(allowed(value, ['schema_version', 'publication_id', 'generated_at_utc', 'results_sha256']), 'Unexpected manifest fields.');
  assert(versions.has(value.schema_version), 'This publication format is not supported.');
  assert(typeof value.publication_id === 'string' && /^[A-Za-z0-9][A-Za-z0-9._-]{0,119}$/.test(value.publication_id), 'Invalid publication identifier.');
  const empty = value.schema_version === '1.0.0' && value.publication_id === 'not-published';
  assert(time(value.generated_at_utc) || (empty && value.generated_at_utc === null), 'Invalid publication time.');
  if (value.schema_version === '2.0.0' || value.results_sha256 !== undefined) {
    assert(typeof value.results_sha256 === 'string' && hex.test(value.results_sha256), 'Missing or invalid snapshot checksum.');
  }
  return value;
}

export function validateResults(value) {
  assert(object(value) && allowed(value, ['metadata', 'cells', 'matrix_cells']), 'Invalid aggregate snapshot.');
  const m = value.metadata;
  assert(object(m), 'Missing publication metadata.');
  assert(allowed(m, ['schema_version', 'publication_id', 'generated_at_utc', 'source_snapshot_at_utc', 'minimum_cell_size', 'classification_note', 'data_mode', 'data_note', 'rollback_of', 'window_start_utc', 'window_end_utc', 'selection_rule', 'classification_version', 'privacy_version', 'content_fingerprint', 'class_source_at_utc', 'reference_source_at_utc']), 'Unexpected aggregate metadata.');
  validateManifest({ schema_version: m.schema_version, publication_id: m.publication_id, generated_at_utc: m.generated_at_utc, ...(m.schema_version === '2.0.0' ? { results_sha256: '0'.repeat(64) } : {}) });
  assert(integer(m.minimum_cell_size) && m.minimum_cell_size >= 2, 'Invalid privacy metadata.');
  assert(text(m.classification_note), 'Missing classification description.');
  assert(Array.isArray(value.cells) && Array.isArray(value.matrix_cells), 'Aggregate tables are missing.');
  assert(value.cells.length <= 10000 && value.matrix_cells.length <= 32000, 'The aggregate snapshot is too large.');
  const empty = m.publication_id === 'not-published' && m.schema_version === '1.0.0';
  if (empty) assert(value.cells.length === 0 && value.matrix_cells.length === 0, 'The unpublished snapshot must be empty.');
  if (m.source_snapshot_at_utc !== undefined) assert(time(m.source_snapshot_at_utc) || (empty && m.source_snapshot_at_utc === null), 'Invalid source time.');
  if (m.data_mode !== undefined) assert(['demonstration', 'qualtrics', 'real', 'survey'].includes(m.data_mode), 'Unknown data mode.');
  if (m.data_note !== undefined) assert(text(m.data_note), 'Invalid data note.');
  if (m.rollback_of !== undefined) assert(text(m.rollback_of), 'Invalid rollback reference.');
  if (m.schema_version === '2.0.0') {
    assert(m.minimum_cell_size >= 5 && ['qualtrics', 'demonstration'].includes(m.data_mode), 'Invalid current publication metadata.');
    for (const field of ['window_start_utc', 'window_end_utc', 'class_source_at_utc', 'reference_source_at_utc']) assert(time(m[field]), 'Missing or invalid source window.');
    assert(m.selection_rule === 'latest_response_hour', 'Unknown group selection rule.');
    assert(Date.parse(m.window_end_utc) - Date.parse(m.window_start_utc) === 3600000, 'The group window must span one hour.');
    assert(text(m.classification_version) && text(m.privacy_version), 'Missing method versions.');
    assert(typeof m.content_fingerprint === 'string' && hex.test(m.content_fingerprint), 'Invalid content fingerprint.');
  }
  for (const [name, isMatrix] of [['cells', false], ['matrix_cells', true]]) {
    const keys = new Set();
    for (const row of value[name]) {
      const dimensions = isMatrix ? ['compassion_level', 'envy_level'] : ['behaviour', 'denominator_type', 'n_complete', 'n_consistent'];
      assert(object(row) && allowed(row, ['scope', 'country', 'gender', 'count', 'denominator_n', 'percentage', 'suppressed', ...dimensions]), 'Unexpected aggregate cell.');
      assert(['class', 'international'].includes(row.scope) && text(row.country) && ['all', 'female', 'male'].includes(row.gender), 'Invalid aggregate dimensions.');
      assert(row.scope !== 'class' || row.country === 'Class', 'Invalid group dimension.');
      assert(typeof row.suppressed === 'boolean', 'Missing privacy status.');
      const measures = ['count', 'denominator_n', 'percentage', ...(isMatrix ? [] : ['n_complete', 'n_consistent'])];
      if (row.suppressed) assert(measures.every((field) => row[field] === null), 'A protected value was not removed.');
      else {
        assert(integer(row.count) && integer(row.denominator_n) && row.denominator_n > 0 && row.count <= row.denominator_n, 'Invalid aggregate counts.');
        assert(row.count >= m.minimum_cell_size && row.denominator_n - row.count >= m.minimum_cell_size, 'The snapshot contains an unprotected small value.');
        assert(Number.isFinite(row.percentage) && row.percentage >= 0 && row.percentage <= 100, 'Invalid percentage.');
        assert(Math.abs(row.percentage - producerPercentage(row.count, row.denominator_n)) < 0.000001, 'The published percentage does not match its counts.');
        if (!isMatrix) assert(nullableInteger(row.n_complete) && nullableInteger(row.n_consistent), 'Invalid sample sizes.');
      }
      if (isMatrix) assert([1, 2, 3, 4].includes(row.compassion_level) && [1, 2, 3, 4].includes(row.envy_level), 'Invalid matrix position.');
      else assert(Object.hasOwn(LABELS, row.behaviour) && row.denominator_type === (row.behaviour === 'inconsistent' ? 'complete' : 'consistent'), 'Invalid indicator denominator.');
      const key = [row.scope, row.country, row.gender, ...(isMatrix ? [row.compassion_level, row.envy_level] : [row.behaviour])].join('\u0001');
      assert(!keys.has(key), 'Duplicate aggregate cell.');
      keys.add(key);
    }
  }
  return value;
}
