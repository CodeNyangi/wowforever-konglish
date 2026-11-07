import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';

export const overlayExecutable = fileURLToPath(new URL(
  '../.build/Konglish Overlay.app/Contents/MacOS/konglish-overlay', import.meta.url,
));

export function createChatOverlay({ settings, onUpdate, onForeground, executable = overlayExecutable }) {
  let active;

  function stop() {
    const previous = active;
    active = undefined;
    if (!previous) return;
    previous.stdin.end();
    previous.kill();
    onForeground(false);
    onUpdate({ running: false, text: '오버레이 꺼짐' });
  }

  function start() {
    stop();
    const child = spawn(executable, [settings], { stdio: ['pipe', 'pipe', 'ignore'] });
    active = child;
    onUpdate({ running: true, text: '와우 창을 찾는 중이에요.' });
    child.stdin.on('error', () => {});

    const reader = createInterface({ input: child.stdout });
    let failed = false;
    reader.on('line', line => {
      if (child !== active || line.length > 4096) return;
      let event;
      try { event = JSON.parse(line); } catch { return; }
      if (typeof event?.text !== 'string') return;
      if (event.kind === 'foreground') {
        onForeground(event.text === 'wow');
      } else if (['status', 'warning', 'error'].includes(event.kind)) {
        failed ||= event.kind === 'error';
        onUpdate({ running: !failed, text: event.text, error: event.kind !== 'status' });
      }
    });

    child.once('error', () => {
      if (child !== active) return;
      stop();
      onUpdate({ running: false, text: '오버레이를 시작하지 못했어요. 앱을 다시 실행해 주세요.', error: true });
    });
    child.once('close', () => {
      reader.close();
      if (child !== active) return;
      active = undefined;
      onForeground(false);
      if (!failed) onUpdate({ running: false, text: '오버레이 꺼짐' });
    });
  }

  function command(action) {
    if (active?.stdin.writable) active.stdin.write(JSON.stringify({ action }) + '\n');
  }

  return { start, stop, reselect: () => command('reselect'), translateDraft: () => command('draft') };
}
