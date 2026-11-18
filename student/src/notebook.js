export function setupNotebook(root) {
  const fields = [...root.querySelectorAll('textarea')];
  const download = root.querySelector('#download-notes');
  const status = root.querySelector('#note-status');
  const key = 'rihm:reflection:v1';
  let canStore = true;

  try {
    const saved = JSON.parse(sessionStorage.getItem(key) || '{}');
    for (const field of fields) {
      if (typeof saved?.[field.id] === 'string') field.value = saved[field.id];
    }
  } catch {
    // A browser can block storage while still allowing writing and downloads.
  }

  function update() {
    const answered = fields.filter(field => field.value.trim()).length;
    download.disabled = answered === 0;
    const message = !canStore ? 'Browser storage is unavailable. Download your notes before leaving this page.'
      : answered ? `${answered} of ${fields.length} prompts answered in this tab.` : '';
    if (status.textContent !== message) status.textContent = message;
  }

  root.addEventListener('input', () => {
    try {
      sessionStorage.setItem(key, JSON.stringify(Object.fromEntries(fields.map(field => [field.id, field.value]))));
    } catch {
      canStore = false;
    }
    update();
  });
  download.addEventListener('click', () => {
    const entries = fields.filter(field => field.value.trim()).map(field =>
      [field.closest('details').querySelector('summary').textContent, field.labels[0].textContent, field.value.trim()].join('\n'));
    const url = URL.createObjectURL(new Blob([['RIHM Decision Lab', ...entries].join('\n\n')], { type: 'text/plain;charset=utf-8' }));
    const link = document.createElement('a');
    link.href = url;
    link.download = 'rihm-reflection.txt';
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  });
  update();
}
