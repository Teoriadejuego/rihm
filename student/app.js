import { createSnapshotReader, createSnapshotStore, startRefresh } from './src/snapshot.js';
import { createView } from './src/view.js';
const selection = { country: 'All Countries', gender: 'all', scope: 'class', behaviours: new Set(['altruist', 'egalitarian', 'selfish', 'antisocial']) };
const root = document.getElementById('snapshotView');
let state = { snapshot: null, checking: true, checkedAt: null, error: null };
let store;
function paint(next = state) {
  state = next;
  const activeId = root.contains(document.activeElement) ? document.activeElement.id : null;
  const openDetails = [...root.querySelectorAll('details[open]')].map((node) => node.id);
  const view = createView(state, selection, { onSelection: (key, value) => { selection[key] = value; paint(); }, onRefresh: () => store.check() });
  root.replaceChildren(view);
  for (const id of openDetails) { const node = document.getElementById(id); if (node) node.open = true; }
  if (activeId) document.getElementById(activeId)?.focus({ preventScroll: true });
}
store = createSnapshotStore({ read: createSnapshotReader(), onChange: paint });
startRefresh(store);
