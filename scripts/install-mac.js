import { execFileSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, utimesSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const require = createRequire(import.meta.url);
const electronBundle = dirname(dirname(dirname(require('electron'))));
const identifier = 'com.wowforever.konglish';
const installed = '/Applications/Konglish.app';
const scratch = join(root, 'work/disposable');
const plist = '/usr/libexec/PlistBuddy';
const version = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).version;

function set(file, key, value) {
  try {
    execFileSync(plist, ['-c', `Set :${key} ${value}`, file], { stdio: 'pipe' });
  } catch {
    execFileSync(plist, ['-c', `Add :${key} string ${value}`, file]);
  }
}

if (existsSync(installed)) {
  const id = execFileSync(plist, ['-c', 'Print :CFBundleIdentifier', join(installed, 'Contents/Info.plist')],
    { encoding: 'utf8' }).trim();
  if (id !== identifier) throw new Error('An unrelated app already uses /Applications/Konglish.app.');
}

mkdirSync(scratch, { recursive: true });
const stage = mkdtempSync(join(scratch, 'konglish-install-'));
const bundle = join(stage, 'Konglish.app');
const backup = join(stage, 'Previous Konglish.app');
try {
  execFileSync('/usr/bin/ditto', [electronBundle, bundle], { stdio: 'inherit' });
  const contents = join(bundle, 'Contents');
  const info = join(contents, 'Info.plist');
  renameSync(join(contents, 'MacOS/Electron'), join(contents, 'MacOS/Konglish'));
  set(info, 'CFBundleName', 'Konglish');
  set(info, 'CFBundleDisplayName', 'Konglish');
  set(info, 'CFBundleExecutable', 'Konglish');
  set(info, 'CFBundleIdentifier', identifier);
  set(info, 'CFBundleShortVersionString', version);
  set(info, 'CFBundleVersion', version);
  set(info, 'LSMinimumSystemVersion', '26.0');
  for (const suffix of ['', ' (GPU)', ' (Plugin)', ' (Renderer)']) {
    const helper = join(contents, 'Frameworks', `Electron Helper${suffix}.app/Contents/Info.plist`);
    if (!existsSync(helper)) continue;
    const variant = suffix.toLowerCase().replace(/[^a-z]/g, '');
    set(helper, 'CFBundleIdentifier', identifier + '.helper' + (variant ? '.' + variant : ''));
    set(helper, 'CFBundleName', `Konglish Helper${suffix}`);
    set(helper, 'CFBundleDisplayName', `Konglish Helper${suffix}`);
  }

  const resources = join(contents, 'Resources');
  cpSync(join(dirname(electronBundle), 'LICENSE'), join(resources, 'LICENSE.Electron'));
  cpSync(join(dirname(electronBundle), 'LICENSES.chromium.html'), join(resources, 'LICENSES.chromium.html'));
  const application = join(resources, 'app');
  mkdirSync(application);
  for (const entry of ['desktop', 'package.json', 'LICENSE', '.build/Konglish Overlay.app']) {
    cpSync(join(root, entry), join(application, entry), { recursive: true, filter: source => !source.endsWith('/desktop/native') });
  }
  execFileSync('/usr/bin/codesign', ['--force', '--deep', '--sign', '-', bundle], { stdio: 'inherit' });
  execFileSync('/usr/bin/codesign', ['--verify', '--deep', '--strict', bundle], { stdio: 'inherit' });
  if (existsSync(installed)) renameSync(installed, backup);
  try {
    renameSync(bundle, installed);
  } catch (error) {
    if (existsSync(backup)) renameSync(backup, installed);
    throw error;
  }
  const now = new Date();
  utimesSync(installed, now, now);
  execFileSync('/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister',
    ['-f', installed]);
  console.log(installed);
} finally {
  if (existsSync(installed) || !existsSync(backup)) rmSync(stage, { recursive: true, force: true });
}
