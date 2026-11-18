import { describe, it, expect } from 'vitest';
import { validateResults, validateManifest } from '../../student/src/contract.js';
import { createModel, difference, valueLabel } from '../../student/src/model.js';
import { fixture, emptyFixture, bundle, protect } from './fixtures.js';
import producerCases from './r-percentage-cases.json';
describe('public aggregate contracts', () => {
  it.each(producerCases.cases)('accepts the independent R percentage $count/$denominator = $percentage ($case)', (sample) => {
    const data = fixture();
    for (const name of ['cells', 'matrix_cells']) {
      Object.assign(data[name][0], { count: sample.count, denominator_n: sample.denominator, percentage: sample.percentage });
      if (name === 'cells') Object.assign(data[name][0], { n_consistent: sample.denominator, n_complete: sample.denominator + 11 });
    }
    expect(validateResults(data)).toBe(data);
    data.cells[0].percentage = sample.percentage + 0.1;
    expect(() => validateResults(data)).toThrow(/percentage does not match/);
  });
  it('accepts the unchanged legacy unpublished snapshot', () => { const data = emptyFixture(); expect(validateResults(data)).toBe(data); expect(validateManifest(bundle(data).manifest)).toBeDefined(); });
  it('reads populated legacy and current formats', () => { expect(validateResults(fixture({ version: '1.0.0' }))).toBeDefined(); expect(validateResults(fixture())).toBeDefined(); });
  it('accepts the producer data mode for a real aggregate', () => { const data = fixture(); data.metadata.data_mode = 'qualtrics'; delete data.metadata.data_note; expect(validateResults(data)).toBeDefined(); });
  it('rejects unknown versions, absent checksums and malformed checksums', () => {
    const m = bundle().manifest; for (const bad of [{ ...m, schema_version: '3.0.0' }, { ...m, results_sha256: undefined }, { ...m, results_sha256: 'bad' }]) expect(() => validateManifest(bad)).toThrow();
  });
  it('requires v2 method provenance and historical one-hour window', () => {
    for (const field of ['window_start_utc', 'window_end_utc', 'selection_rule', 'classification_version', 'privacy_version', 'content_fingerprint', 'class_source_at_utc', 'reference_source_at_utc']) {
      const data = fixture(); delete data.metadata[field]; expect(() => validateResults(data)).toThrow();
    }
    const data = fixture(); data.metadata.window_start_utc = '2020-03-04T07:00:00Z'; expect(() => validateResults(data)).toThrow(/one hour/);
  });
  it('never substitutes the current clock for a historical window', () => { const data = fixture(); expect(validateResults(data).metadata.window_end_utc).toBe('2020-03-04T09:00:00Z'); });
  it('rejects extra fields at the root, metadata and cell level', () => {
    for (const mutate of [(d) => { d.responses = []; }, (d) => { d.metadata.email = 'private'; }, (d) => { d.cells[0].answer = 1; }]) { const data = fixture(); mutate(data); expect(() => validateResults(data)).toThrow(); }
  });
  it('accepts fully redacted cells and rejects a leaked protected measure', () => { const data = fixture(); protect(data.cells[0]); expect(validateResults(data)).toBeDefined(); data.cells[0].count = 1; expect(() => validateResults(data)).toThrow(/protected value/); });
  it('rejects duplicate dimensions and mismatched denominators', () => { const data = fixture(); data.cells.push({ ...data.cells[0] }); expect(() => validateResults(data)).toThrow(/Duplicate/); const other = fixture(); other.cells[0].denominator_type = 'complete'; expect(() => validateResults(other)).toThrow(/denominator/); });
  it('rejects malformed measures without attempting privacy recomputation', () => { for (const bad of [NaN, Infinity, -1, 101, '40']) { const data = fixture(); data.cells[0].percentage = bad; expect(() => validateResults(data)).toThrow(); } });
  it('rejects unprotected small counts, complements and inconsistent percentages', () => {
    for (const mutate of [(d) => { d.cells[0].count = 4; }, (d) => { d.cells[0].count = d.cells[0].denominator_n - 4; }, (d) => { d.cells[0].percentage = 99; }, (d) => { d.metadata.minimum_cell_size = 2; }]) { const data = fixture(); mutate(data); expect(() => validateResults(data)).toThrow(); }
  });
});
describe('local display model', () => {
  const selection = () => ({ country: 'Spain', gender: 'all', behaviours: new Set(['altruist']), scope: 'class' });
  it('preserves an available country and falls back for a removed one', () => { expect(createModel(fixture(), selection()).country).toBe('Spain'); expect(createModel(fixture(), { ...selection(), country: 'Missing' }).country).toBe('All Countries'); });
  it('reads consistent sample size even when complete count is protected', () => { const data = fixture(); for (const c of data.cells) if (c.scope === 'class') c.n_complete = null; const model = createModel(data, selection()); expect(model.sample('class', 'n_complete')).toBeNull(); expect(model.sample('class', 'n_consistent')).toBeGreaterThan(0); });
  it('distinguishes zero, protected and unavailable values', () => { expect(valueLabel({ percentage: 0, suppressed: false })).toBe('0.0%'); expect(valueLabel({ percentage: null, suppressed: true })).toBe('Protected'); expect(valueLabel()).toBe('Unavailable'); });
  it('only computes differences from two visible published percentages', () => { const g = { percentage: 30, suppressed: false }, r = { percentage: 35.1, suppressed: false }; expect(difference(g, r)).toBe(-5.1); expect(difference(g, { ...r, suppressed: true })).toBeNull(); });
});
