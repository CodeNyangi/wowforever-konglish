import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { createChatOverlay } from '../desktop/overlay.js';

test('the companion only exchanges controls and status with the local overlay', { timeout: 3500 }, async () => {
  const fixture = fileURLToPath(new URL('./overlay-worker.js', import.meta.url));
  const foreground = [];
  const received = [];
  let finish;
  const commands = new Promise(resolve => { finish = resolve; });
  const overlay = createChatOverlay({
    executable: process.execPath,
    settings: fixture,
    onForeground(value) { foreground.push(value); },
    onUpdate(update) {
      if (update.text === 'fixture ready') {
        overlay.reselect();
        overlay.translateDraft();
      } else if (update.text.startsWith('{')) {
        received.push(JSON.parse(update.text));
        if (received.length === 2) finish();
      }
    },
  });
  try {
    overlay.start();
    await commands;
    assert.deepEqual(received, [{ action: 'reselect' }, { action: 'draft' }]);
    assert.deepEqual(foreground, [true]);
  } finally {
    overlay.stop();
  }
  assert.deepEqual(foreground, [true, false]);
});
