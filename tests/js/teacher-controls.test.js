import { describe, it, expect, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const source = readFileSync(new URL('../../admin/www/research.js', import.meta.url), 'utf8');

function harness({ lateShiny = false } = {}) {
  const native = new Map(), lifecycle = new Map(), handlers = new Map(), elements = new Map();
  const document = {
    readyState: 'loading', fullscreenElement: null,
    addEventListener: (name, handler) => native.set(name, handler),
    getElementById: (id) => elements.get(id) ?? null,
    exitFullscreen: vi.fn(async () => {})
  };
  const shiny = {
    setInputValue: vi.fn(),
    addCustomMessageHandler: vi.fn((name, handler) => handlers.set(name, handler))
  };
  const window = {
    jQuery: () => ({ on: (name, handler) => lifecycle.set(name.split('.')[0], handler) })
  };
  if (!lateShiny) window.Shiny = shiny;
  runInNewContext(source, { window, document });
  return { window, document, shiny, native, lifecycle, handlers, elements,
    addButton(id) {
      const button = { id, disabled: false };
      elements.set(id, button);
      lifecycle.get('shiny:bound')({ target: button });
      return button;
    }
  };
}

describe('private teacher controls', () => {
  it('registers messages through the real jQuery lifecycle, once across connections', () => {
    const h = harness();
    expect(h.native.has('shiny:connected')).toBe(false);
    h.lifecycle.get('shiny:connected')();
    h.lifecycle.get('shiny:connected')();
    expect(h.handlers.has('teacher-controls')).toBe(true);
    expect(h.handlers.has('teacher-exit-fullscreen')).toBe(true);
    expect(h.shiny.addCustomMessageHandler).toHaveBeenCalledTimes(2);
  });

  it('keeps freshly inserted buttons disabled until the server enables them', () => {
    const h = harness(), update = h.addButton('update_publish'), demo = h.addButton('load_demo');
    expect(update.disabled).toBe(true);
    expect(demo.disabled).toBe(true);
    const message = h.handlers.get('teacher-controls');
    message({ update_publish: false, refresh_latest: true, load_demo: true, cancel_operation: false });
    expect(update.disabled).toBe(true);
    expect(demo.disabled).toBe(false);
    message({ update_publish: true, refresh_latest: true, load_demo: true, cancel_operation: false });
    expect(update.disabled).toBe(false);
    message({ update_publish: false, refresh_latest: false, load_demo: false, cancel_operation: true });
    expect(update.disabled).toBe(true);
    expect(demo.disabled).toBe(true);
    expect(h.addButton('cancel_operation').disabled).toBe(false);
  });

  it('applies messages received before authentication inserts the controls', () => {
    const h = harness();
    h.handlers.get('teacher-controls')({ update_publish: false, load_demo: true });
    expect(h.addButton('update_publish').disabled).toBe(true);
    expect(h.addButton('load_demo').disabled).toBe(false);
  });

  it('fails closed on disconnect, return to login and malformed permissions', () => {
    const h = harness(), update = h.addButton('update_publish');
    const message = h.handlers.get('teacher-controls');
    message({ update_publish: true });
    h.lifecycle.get('shiny:disconnected')();
    expect(update.disabled).toBe(true);
    message({ update_publish: true });
    h.lifecycle.get('shiny:bound')({ target: { id: 'teacher_login-user_id' } });
    expect(update.disabled).toBe(true);
    message({ update_publish: 'true' });
    expect(update.disabled).toBe(true);
    message(null);
    expect(update.disabled).toBe(true);
  });

  it('handles deferred Shiny initialisation and the fullscreen exit message', async () => {
    const h = harness({ lateShiny: true });
    expect(h.handlers.size).toBe(0);
    h.window.Shiny = h.shiny;
    h.lifecycle.get('shiny:connected')();
    h.native.get('DOMContentLoaded')();
    expect(h.shiny.addCustomMessageHandler).toHaveBeenCalledTimes(2);
    h.document.fullscreenElement = { id: 'presentationStage' };
    h.handlers.get('teacher-exit-fullscreen')();
    await Promise.resolve();
    expect(h.document.exitFullscreen).toHaveBeenCalledTimes(1);
  });
});
