import { createSnapshotReader, createSnapshotStore, startRefresh } from './src/snapshot.js';
import { createView, updateViewStatus } from './src/view.js';
import { setupNotebook } from './src/notebook.js';
setupNotebook(document.getElementById('notebook'));
const selection = { country: 'All Countries', gender: 'all', scope: 'class', behaviours: new Set(['altruist', 'egalitarian', 'selfish', 'antisocial']) };
const root = document.getElementById('snapshotView');
let state = { snapshot: null, checking: true, checkedAt: null, error: null };
let store;
let mounted = false;
let renderedSnapshot = null;
function paint(next = state, selectionChanged = false) {
  state = next;
  // Manifest checks and failures do not change the aggregate object. Keep
  // every chart, control and disclosure node intact during those checks.
  if (mounted && renderedSnapshot === state.snapshot && !selectionChanged) {
    updateViewStatus(root, state);
    return;
  }
  const activeId = root.contains(document.activeElement) ? document.activeElement.id : null;
  const openDetails = [...root.querySelectorAll('details[open]')].map((node) => node.id);
  const scrollPositions = [...root.querySelectorAll('[id]')]
    .filter((node) => node.scrollLeft || node.scrollTop)
    .map((node) => ({ id: node.id, left: node.scrollLeft, top: node.scrollTop }));
  const viewport = { left: window.scrollX, top: window.scrollY };
  const view = createView(state, selection, {
    onSelection: (key, value) => { selection[key] = value; paint(state, true); },
    onClassExample: () => {
      selection.country = 'Madagascar';
      selection.gender = 'all';
      selection.behaviours.add('egalitarian');
      paint(state, true);
      document.getElementById('example-reading')?.focus();
    },
    onRefresh: () => store.check()
  });
  root.replaceChildren(view);
  mounted = true;
  renderedSnapshot = state.snapshot;
  for (const id of openDetails) { const node = document.getElementById(id); if (node) node.open = true; }
  for (const position of scrollPositions) {
    const node = document.getElementById(position.id);
    if (node) { node.scrollLeft = position.left; node.scrollTop = position.top; }
  }
  if (activeId) document.getElementById(activeId)?.focus({ preventScroll: true });
  window.scrollTo({ ...viewport, behavior: 'instant' });
}
store = createSnapshotStore({ read: createSnapshotReader(), onChange: paint });
startRefresh(store);
