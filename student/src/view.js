import { LABELS, SOCIAL } from './contract.js';
import { createModel, visible, valueLabel, countLabel, difference, dateLabel } from './model.js';
// Published strings always become text nodes, never executable markup.
function el(tag, className, text) { const node = document.createElement(tag); if (className) node.className = className; if (text !== undefined) node.textContent = text; return node; }
function select(id, label, values, selected, change) {
  const wrapper = el('div', 'select-label'), caption = el('label', '', label), input = el('select'); input.id = id; caption.htmlFor = id; wrapper.append(caption);
  for (const [value, text] of values) { const option = el('option', '', text); option.value = value; input.append(option); }
  input.value = selected; input.addEventListener('change', () => change(input.value)); wrapper.append(input); return wrapper;
}
function dataTable(headers, caption) {
  const table = el('table'); table.append(el('caption', '', caption)); const head = el('thead'), tr = el('tr');
  for (const text of headers) { const th = el('th', '', text); th.scope = 'col'; tr.append(th); }
  head.append(tr); const body = el('tbody'); table.append(head, body); return { table, body };
}
const pp = (value) => value === null ? 'Unavailable' : `${value > 0 ? '+' : ''}${value.toFixed(1)} pp`;
function bar(cell, label, kind) {
  const row = el('div', `bar-line ${kind}`); row.setAttribute('aria-label', `${label}: ${valueLabel(cell)}`);
  const track = el('span', `bar-track${visible(cell) ? '' : ' protected'}`); track.setAttribute('aria-hidden', 'true');
  if (visible(cell)) { const fill = el('span', 'bar-fill'); fill.style.width = `${cell.percentage}%`; track.append(fill); }
  row.append(el('span', 'bar-name', label), track, el('strong', 'bar-value', valueLabel(cell))); return row;
}
function chart(model) {
  const section = el('section', 'comparison-chart'); section.setAttribute('aria-labelledby', 'chartHeading');
  const heading = el('div', 'chart-heading'), title = el('h3', '', 'Four indicators, shared patterns'); title.id = 'chartHeading';
  heading.append(title, el('p', '', 'Percent of consistent responses. Indicators can overlap.')); section.append(heading);
  const legend = el('div', 'legend'); legend.append(el('span', 'group-key', 'Latest group'), el('span', 'reference-key', model.country)); section.append(legend);
  if (!model.selected.length) section.append(el('p', 'empty-selection', 'Select at least one indicator to compare.'));
  for (const name of model.selected) {
    const block = el('div', 'indicator-block'); block.dataset.indicator = name;
    const group = model.cell('class', name), reference = model.cell('international', name), heading = el('div', 'indicator-heading');
    heading.append(el('h4', '', LABELS[name]), el('span', 'difference', pp(difference(group, reference))));
    block.append(heading, bar(group, 'Group', 'group'), bar(reference, 'Reference', 'reference')); section.append(block);
  }
  const scale = el('div', 'bar-scale'); scale.setAttribute('aria-hidden', 'true'); scale.append(el('span', '', '0%'), el('span', '', '50%'), el('span', '', '100%')); section.append(scale); return section;
}
function matrix(data, model, selection, actions) {
  const section = el('section', 'matrix-section'), h = el('h3', '', 'Compassion × envy'); h.id = 'matrixHeading'; section.setAttribute('aria-labelledby', h.id);
  section.append(h, el('p', '', 'Sixteen consistent patterns. Read across for more envy, upward for more compassion.'));
  section.append(select('matrixScope', 'Matrix sample', [['class', 'Latest group'], ['international', 'Reference']], selection.scope, (v) => actions.onSelection('scope', v)));
  const country = selection.scope === 'class' ? 'Class' : model.country;
  const rows = data.matrix_cells.filter((c) => c.scope === selection.scope && c.country === country && c.gender === selection.gender);
  const { table, body } = dataTable(['Compassion / envy', '1', '2', '3', '4'], `${selection.scope === 'class' ? 'Latest group' : model.country}: percent of consistent responses`);
  table.className = 'matrix-table'; table.id = 'matrixTable';
  for (let compassion = 4; compassion >= 1; compassion -= 1) {
    const tr = el('tr'), header = el('th', '', `${compassion}`); header.scope = 'row'; header.setAttribute('aria-label', `Compassion ${compassion}`); tr.append(header);
    for (let envy = 1; envy <= 4; envy += 1) {
      const cell = rows.find((c) => c.compassion_level === compassion && c.envy_level === envy);
      const td = el('td', visible(cell) ? 'matrix-value' : 'matrix-protected');
      td.append(el('strong', '', valueLabel(cell)), el('span', 'matrix-count', visible(cell) ? `${countLabel(cell.count)} / ${countLabel(cell.denominator_n)}` : cell ? 'Withheld' : 'No cell'));
      td.setAttribute('aria-label', `Compassion ${compassion}, envy ${envy}: ${valueLabel(cell)}${visible(cell) ? `, ${cell.count} of ${cell.denominator_n}` : ''}`);
      if (visible(cell)) td.style.backgroundColor = `rgba(48, 87, 157, ${Math.min(0.32, 0.05 + cell.percentage / 160)})`;
      tr.append(td);
    }
    body.append(tr);
  }
  section.append(table, el('p', 'matrix-note', 'Each square uses the same consistent-response denominator within this sample. Protected values remain hidden.')); return section;
}
function metrics(model) {
  const dl = el('dl', 'sample-metrics'); dl.setAttribute('aria-label', 'Published sample sizes');
  for (const [label, scope, field] of [['Group consistent', 'class', 'n_consistent'], ['Reference consistent', 'international', 'n_consistent'], ['Group complete', 'class', 'n_complete'], ['Reference complete', 'international', 'n_complete']]) {
    const item = el('div'); item.append(el('dt', '', label), el('dd', '', countLabel(model.sample(scope, field)))); dl.append(item);
  }
  return dl;
}
function differenceChart(model) {
  const section = el('section', 'difference-chart'); section.id = 'compare'; section.setAttribute('aria-labelledby', 'differenceHeading');
  const heading = el('h3', '', 'Where the samples differ'); heading.id = 'differenceHeading';
  section.append(heading, el('p', '', 'Group minus reference, in percentage points. Left: higher in the reference. Right: higher in the group.'));
  if (!model.selected.length) section.append(el('p', 'empty-selection', 'Select an indicator to see its difference.'));
  for (const name of model.selected) {
    const value = difference(model.cell('class', name), model.cell('international', name));
    const row = el('div', 'difference-row'); row.dataset.difference = name;
    row.setAttribute('aria-label', `${LABELS[name]}: ${value === null ? 'difference unavailable' : `${value.toFixed(1)} percentage points, group minus reference`}`);
    const plot = el('span', 'difference-track'); plot.setAttribute('aria-hidden', 'true');
    if (value !== null) { const fill = el('span', value < 0 ? 'difference-fill negative' : 'difference-fill'); fill.style.left = `${50 + Math.min(0, value) / 2}%`; fill.style.width = `${Math.abs(value) / 2}%`; plot.append(fill); }
    row.append(el('span', 'difference-label', LABELS[name]), plot, el('strong', 'difference-value', pp(value))); section.append(row);
  }
  const axis = el('div', 'difference-axis'); axis.setAttribute('aria-hidden', 'true'); axis.append(el('span', '', '−100 pp'), el('span', '', '0'), el('span', '', '+100 pp')); section.append(axis); return section;
}
function comparisonTable(model) {
  const details = el('details', 'comparison-details'); details.id = 'comparisonDetails'; const summary = el('summary', '', 'Compare the exact counts and denominators'); summary.id = 'comparisonSummary'; details.append(summary);
  const { table, body } = dataTable(['Indicator', 'Group count / n', 'Group %', 'Reference count / n', 'Reference %', 'Group − reference', 'Denominator'], 'All displayed values come from the published aggregate. pp means percentage points.'); table.id = 'comparisonTable';
  for (const name of [...model.selected, 'inconsistent']) {
    const g = model.cell('class', name), r = model.cell('international', name), row = el('tr'), th = el('th', '', LABELS[name]); th.scope = 'row'; row.append(th);
    for (const text of [visible(g) ? `${countLabel(g.count)} / ${countLabel(g.denominator_n)}` : g ? 'Protected' : 'Unavailable', valueLabel(g), visible(r) ? `${countLabel(r.count)} / ${countLabel(r.denominator_n)}` : r ? 'Protected' : 'Unavailable', valueLabel(r), pp(difference(g, r)), name === 'inconsistent' ? 'Complete binary' : 'Consistent']) row.append(el('td', '', text)); body.append(row);
  }
  const scroll = el('div', 'table-scroll'); scroll.id = 'comparisonScroll'; scroll.tabIndex = 0; scroll.setAttribute('aria-label', 'Scrollable comparison table'); scroll.append(table); details.append(scroll); return details;
}
function publicationDetails(m) {
  const details = el('details', 'publication-details'); details.id = 'publicationDetails'; const summary = el('summary', '', 'Publication and method details'); summary.id = 'publicationSummary'; details.append(summary); const dl = el('dl', 'publication-list');
  for (const [label, value] of [['Publication', m.publication_id], ['Published', dateLabel(m.generated_at_utc)], ['Format', m.schema_version], ['Group source downloaded', m.class_source_at_utc ? dateLabel(m.class_source_at_utc) : m.source_snapshot_at_utc ? dateLabel(m.source_snapshot_at_utc) : 'Not available'], ['Reference source downloaded', m.reference_source_at_utc ? dateLabel(m.reference_source_at_utc) : 'Not available in this publication'], ['Classification', m.classification_version || 'Original classification (legacy format)'], ['Privacy method', m.privacy_version || 'Original suppression (legacy format)'], ['Protection threshold', `${m.minimum_cell_size}`], ['Content fingerprint', m.content_fingerprint || 'Not available in this publication']]) dl.append(el('dt', '', label), el('dd', '', value));
  details.append(dl); return details;
}
function comparisonMessage(state) {
  if (state.error) return 'Comparisons are unavailable until a verified publication can be loaded. Use Check for updates to try again.';
  return state.snapshot ? 'Comparisons will appear here after the researcher publishes a protected group aggregate.' : 'Comparisons will appear here once the latest publication has been verified.';
}
function emptyComparison(state) {
  const section = el('section', 'difference-chart'); section.id = 'compare'; section.setAttribute('aria-labelledby', 'differenceHeading');
  const heading = el('h3', '', 'Where the samples differ'); heading.id = 'differenceHeading';
  const message = el('p', '', comparisonMessage(state)); message.id = 'emptyComparisonMessage';
  section.append(heading, message); return section;
}
// Updating operational status never replaces the data view or its controls.
export function updateViewStatus(root, state) {
  const status = root.querySelector('#dataStatus');
  const message = state.checking ? 'Checking the latest publication…' : state.error ? state.snapshot ? 'Update unavailable. The last verified publication remains on screen.' : 'The publication could not be loaded. Try checking again.' : state.snapshot?.data.cells.length ? `Publication checked ${state.checkedAt ? new Intl.DateTimeFormat('en-GB', { timeStyle: 'short' }).format(state.checkedAt) : 'now'}. Checks repeat every minute while this page is visible.` : 'Ready for results. The researcher has not published a group yet.';
  if (status.textContent !== message) status.textContent = message;
  const statusClass = state.error ? 'status warning' : 'status';
  if (status.className !== statusClass) status.className = statusClass;
  const refresh = root.querySelector('#refreshButton');
  const refreshText = state.checking ? 'Checking…' : 'Check for updates';
  if (refresh.textContent !== refreshText) refresh.textContent = refreshText;
  refresh.setAttribute('aria-disabled', String(state.checking));
  const error = root.querySelector('#initialLoadError');
  if (error) {
    const errorText = state.error || '';
    if (error.textContent !== errorText) error.textContent = errorText;
    error.hidden = !state.error;
  }
  const placeholder = root.querySelector('#emptyComparisonMessage');
  if (placeholder && placeholder.textContent !== comparisonMessage(state)) placeholder.textContent = comparisonMessage(state);
}
export function createView(state, selection, actions) {
  const fragment = document.createDocumentFragment(), update = el('div', 'update-strip'), status = el('p', 'status'); status.id = 'dataStatus'; status.setAttribute('role', 'status');
  const refresh = el('button', 'refresh-button'); refresh.type = 'button'; refresh.id = 'refreshButton';
  refresh.addEventListener('click', () => { if (refresh.getAttribute('aria-disabled') !== 'true') actions.onRefresh(); }); update.append(status, refresh); fragment.append(update);
  if (!state.snapshot) {
    const error = el('p', 'error-detail'); error.id = 'initialLoadError'; error.hidden = true;
    fragment.append(error, emptyComparison(state)); updateViewStatus(fragment, state); return fragment;
  }
  updateViewStatus(fragment, state);
  const data = state.snapshot.data, m = data.metadata;
  if (m.data_mode === 'demonstration') { const notice = el('aside', 'demo-notice'); notice.id = 'demoNotice'; notice.append(el('strong', '', 'Synthetic demonstration'), el('span', '', 'Generated examples for testing. These results do not describe real people, countries or genders.')); fragment.append(notice); }
  const publication = el('div', 'publication-strip'); publication.id = 'publicationMeta'; publication.append(el('span', '', `Published ${dateLabel(m.generated_at_utc)}`), el('span', 'publication-id', m.publication_id)); fragment.append(publication);
  if (!data.cells.length) { fragment.append(el('div', 'empty-results', 'The game and methods are available now. Group comparisons will appear here after a protected aggregate is published.'), emptyComparison(state)); return fragment; }
  const model = createModel(data, selection); selection.country = model.country;
  const groupWindow = el('div', 'group-window'); groupWindow.id = 'groupWindow';
  if (m.schema_version === '2.0.0') groupWindow.append(el('strong', '', 'Latest recorded group'), el('span', '', `${dateLabel(m.window_start_utc)} to ${dateLabel(m.window_end_utc)}`), el('p', '', 'The hour ending at the latest recorded response in the downloaded data. Historical responses keep their original window; this is not the hour before you opened the page.'));
  else groupWindow.append(el('strong', '', 'Published group'), el('p', '', 'This earlier publication does not include a recorded one-hour selection window.'));
  fragment.append(groupWindow);
  const filters = el('form', 'filters'); filters.setAttribute('aria-label', 'Comparison filters'); filters.addEventListener('submit', (event) => event.preventDefault());
  filters.append(select('countrySelect', 'Reference country', model.countries.map((c) => [c, c]), model.country, (v) => actions.onSelection('country', v)), select('genderSelect', 'Gender', [['all', 'All respondents'], ['female', 'Female'], ['male', 'Male']], selection.gender, (v) => actions.onSelection('gender', v)));
  const fieldset = el('fieldset'); fieldset.append(el('legend', '', 'Social indicators')); const checks = el('div', 'indicator-controls');
  for (const name of SOCIAL) { const label = el('label'), input = el('input'); input.type = 'checkbox'; input.id = `indicator-${name}`; input.checked = selection.behaviours.has(name); input.addEventListener('change', () => { const value = new Set(selection.behaviours); if (input.checked) value.add(name); else value.delete(name); actions.onSelection('behaviours', value); }); label.append(input, document.createTextNode(LABELS[name])); checks.append(label); }
  fieldset.append(checks); filters.append(fieldset); fragment.append(filters, metrics(model));
  const grid = el('div', 'data-grid'); grid.append(chart(model), matrix(data, model, selection, actions)); fragment.append(grid, differenceChart(model));
  const inconsistent = el('section', 'inconsistent-section'); inconsistent.append(el('h3', '', 'Inconsistent responses'), el('p', '', 'Reported separately: percentage of complete binary responses, including consistent and inconsistent patterns.')); const bars = el('div', 'inconsistent-bars'); bars.append(bar(model.cell('class', 'inconsistent'), 'Group', 'group'), bar(model.cell('international', 'inconsistent'), 'Reference', 'reference')); inconsistent.append(bars); fragment.append(inconsistent, comparisonTable(model), publicationDetails(m)); return fragment;
}
