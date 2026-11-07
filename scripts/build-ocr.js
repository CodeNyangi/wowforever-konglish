import { copyFileSync, mkdirSync, statSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

if (process.platform !== 'darwin') {
  throw new Error('The Konglish companion currently targets macOS.');
}

const project = new URL('../', import.meta.url);
const native = new URL('desktop/native/', project);
const build = new URL('.build/', project);
const overlay = new URL('Konglish Overlay.app/Contents/', build);
const arch = process.arch === 'arm64' ? 'arm64' : 'x86_64';
mkdirSync(new URL('MacOS/', overlay), { recursive: true });

function compile(sources, output) {
  const input = sources.map(source => fileURLToPath(new URL(source, native)));
  const target = fileURLToPath(output);
  const builtAt = statSync(target, { throwIfNoEntry: false })?.mtimeMs ?? 0;
  if (input.every(path => statSync(path).mtimeMs <= builtAt) &&
      statSync(fileURLToPath(import.meta.url)).mtimeMs <= builtAt) return false;

  execFileSync('xcrun', ['swiftc', '-O', '-target', `${arch}-apple-macos14.0`, ...input, '-o', target], { stdio: 'inherit' });
  return true;
}

const rebuilt = compile(['OverlayModel.swift', 'OverlayPanels.swift', 'ChatMotion.swift', 'WindowShare.swift', 'LocalTranslation.swift', 'OverlayMain.swift'], new URL('MacOS/konglish-overlay', overlay));
const info = new URL('OverlayInfo.plist', native);
const builtInfo = new URL('Info.plist', overlay);
if (rebuilt || statSync(info).mtimeMs > (statSync(builtInfo, { throwIfNoEntry: false })?.mtimeMs ?? 0)) {
  copyFileSync(info, builtInfo);
  execFileSync('/usr/bin/codesign', ['--force', '--sign', '-', fileURLToPath(new URL('../', overlay))], { stdio: 'inherit' });
}
