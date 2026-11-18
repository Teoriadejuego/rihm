import { createHash } from 'node:crypto';
// These synthetic samples use integer-ratio rounding with ties to even. The
// separate r-percentage-cases.json is the independent producer oracle, including
// floating-point edge cases that this synthetic sample generator does not use.
function fixturePercentage(count, denominator) {
  const scaled = BigInt(count) * 1000n;
  const divisor = BigInt(denominator);
  const digit = scaled / divisor;
  const remainder = scaled % divisor;
  const increment = remainder * 2n > divisor || (remainder * 2n === divisor && digit % 2n === 1n);
  return Number(digit + (increment ? 1n : 0n)) / 10;
}
export function fixture({ id = 'demo-browser-1', seed = 1, version = '2.0.0' } = {}) {
  const metadata = { schema_version: version, publication_id: id, generated_at_utc: '2026-11-17T10:00:00Z', source_snapshot_at_utc: '2026-11-17T09:00:00Z', minimum_cell_size: 5, classification_note: 'Synthetic fixture using overlapping original indicators.', data_mode: 'demonstration', data_note: 'Synthetic data only; no real participants.' };
  if (version === '2.0.0') Object.assign(metadata, { window_start_utc: '2020-03-04T08:00:00Z', window_end_utc: '2020-03-04T09:00:00Z', selection_rule: 'latest_response_hour', classification_version: 'original-1.0.0', privacy_version: 'linked-1.0.0', content_fingerprint: 'a'.repeat(64), class_source_at_utc: '2026-11-17T09:00:00Z', reference_source_at_utc: '2026-11-17T08:00:00Z' });
  const cells = [], matrix_cells = [];
  const countries = ['Dominican Republic', 'Ivory Coast', 'Madagascar', 'Philippines', 'Salvador', 'Spain'];
  const groups = [{ scope: 'class', country: 'Class', number: seed }, ...countries.map((country, i) => ({ scope: 'international', country, number: i + seed + 3 }))];
  const patterns = (number, gender) => Array.from({ length: 16 }, (_, i) => ({ compassion_level: Math.floor(i / 4) + 1, envy_level: i % 4 + 1, count: 5 + (i * (number % 3 + 1) + gender * number + seed) % 9 }));
  const source = groups.map((group) => ({ ...group, female: patterns(group.number, 1), male: patterns(group.number, 2) }));
  source.push({ scope: 'international', country: 'All Countries', number: 30, female: source.slice(1).reduce((a, g) => a.map((p, i) => ({ ...p, count: p.count + g.female[i].count })), patterns(0, 0).map((p) => ({ ...p, count: 0 }))), male: source.slice(1).reduce((a, g) => a.map((p, i) => ({ ...p, count: p.count + g.male[i].count })), patterns(0, 0).map((p) => ({ ...p, count: 0 }))) });
  for (const group of source) for (const gender of ['all', 'female', 'male']) {
    const rows = gender === 'all' ? group.female.map((p, i) => ({ ...p, count: p.count + group.male[i].count })) : group[gender];
    const n = rows.reduce((sum, p) => sum + p.count, 0), inconsistent = gender === 'all' ? 22 : 11;
    const conditions = { altruist: (p) => p.compassion_level >= 2 && p.envy_level <= 2, egalitarian: (p) => p.compassion_level >= 2 && p.envy_level >= 3, selfish: (p) => p.compassion_level <= 2 && p.envy_level >= 2 && p.envy_level <= 3, antisocial: (p) => p.compassion_level === 1 };
    for (const behaviour of [...Object.keys(conditions), 'inconsistent']) {
      const count = behaviour === 'inconsistent' ? inconsistent : rows.filter(conditions[behaviour]).reduce((sum, p) => sum + p.count, 0);
      const denominator_n = behaviour === 'inconsistent' ? n + inconsistent : n;
      cells.push({ scope: group.scope, country: group.country, gender, behaviour, count, denominator_n, percentage: fixturePercentage(count, denominator_n), denominator_type: behaviour === 'inconsistent' ? 'complete' : 'consistent', n_complete: n + inconsistent, n_consistent: n, suppressed: false });
    }
    for (const row of rows) matrix_cells.push({ scope: group.scope, country: group.country, gender, ...row, denominator_n: n, percentage: fixturePercentage(row.count, n), suppressed: false });
  }
  return { metadata, cells, matrix_cells };
}
export const emptyFixture = () => ({ metadata: { schema_version: '1.0.0', publication_id: 'not-published', generated_at_utc: null, source_snapshot_at_utc: null, minimum_cell_size: 5, classification_note: 'Original overlapping indicators.' }, cells: [], matrix_cells: [] });
export function bundle(data = fixture()) {
  const text = `${JSON.stringify(data, null, 2)}\n`;
  const manifest = { schema_version: data.metadata.schema_version, publication_id: data.metadata.publication_id, generated_at_utc: data.metadata.generated_at_utc };
  if (manifest.schema_version === '2.0.0') manifest.results_sha256 = createHash('sha256').update(text, 'utf8').digest('hex');
  return { data, text, manifest };
}
export function protect(cell) {
  cell.suppressed = true;
  for (const name of ['count', 'denominator_n', 'percentage', 'n_complete', 'n_consistent']) if (name in cell) cell[name] = null;
  return cell;
}
