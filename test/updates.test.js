import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, readFile, writeFile, cp, rm, access } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { once } from 'node:events';
import { createUpdater, selectUpdate } from '../desktop/updates.js';

function release(bytes = Buffer.from('zip'), version = '0.1.1') {
  const name = `Konglish-${version}-mac-arm64.zip`;
  return { tag_name: `v${version}`, draft: false, prerelease: false, assets: [{
    name, state: 'uploaded', size: bytes.length,
    digest: `sha256:${createHash('sha256').update(bytes).digest('hex')}`,
    browser_download_url: `https://github.com/CodeNyangi/wowforever-konglish/releases/download/v${version}/${name}`,
  }] };
}

test('updates accept only newer stable releases for this architecture with a GitHub checksum', () => {
  assert.equal(selectUpdate(release(), '0.1.0', 'arm64').version, '0.1.1');
  for (const candidate of [release(Buffer.from('x'), '0.1.0'), { ...release(), prerelease: true }, { ...release(), draft: true }]) {
    assert.equal(selectUpdate(candidate, '0.1.0', 'arm64'), null);
  }
  assert.equal(selectUpdate(release(), '0.1.0', 'x64'), null);
  const foreign = release(); foreign.assets[0].browser_download_url = 'https://example.com/app.zip';
  assert.equal(selectUpdate(foreign, '0.1.0', 'arm64'), null);
  const unchecked = release(); delete unchecked.assets[0].digest;
  assert.equal(selectUpdate(unchecked, '0.1.0', 'arm64'), null);
  assert.equal(selectUpdate(release(Buffer.from('x'), '0.2.0'), '0.10.0', 'arm64'), null);
});

async function fixtureApp(path, version) {
  await mkdir(join(path, 'Contents/MacOS'), { recursive: true });
  await cp('/usr/bin/true', join(path, 'Contents/MacOS/Konglish'));
  await writeFile(join(path, 'Contents/Info.plist'), `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.wowforever.konglish</string><key>CFBundleExecutable</key><string>Konglish</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>${version}</string><key>CFBundleVersion</key><string>${version}</string></dict></plist>`);
  execFileSync('/usr/bin/codesign', ['--force', '--deep', '--sign', '-', path], { stdio: 'pipe' });
}

test('verified update stages without changing the app, preserves opt-out, then installs with a rollback copy', { skip: process.platform !== 'darwin' }, async () => {
  const scratch = resolve('work/disposable');
  await mkdir(scratch, { recursive: true });
  const root = await mkdtemp(join(scratch, 'test-updates-'));
  try {
    const installed = join(root, 'installed/Konglish.app');
    const source = join(root, 'release/Konglish.app');
    await fixtureApp(installed, '0.1.0');
    await fixtureApp(source, '0.1.1');
    const archive = join(root, 'release.zip');
    execFileSync('/usr/bin/ditto', ['-c', '-k', '--sequesterRsrc', '--keepParent', source, archive]);
    const bytes = await readFile(archive);
    const manifest = release(bytes);
    const options = { version: '0.1.0', arch: 'arm64', cacheDir: join(root, 'cache'), installPath: installed,
      fetchImpl: async url => new Response(url.endsWith('/latest') ? JSON.stringify(manifest) : bytes) };
    const updater = createUpdater(options);
    await updater.initialize();
    await updater.check();
    assert.equal(updater.state.ready, true, updater.state.text);
    const pending = JSON.parse(await readFile(join(root, 'cache/pending.json'), 'utf8'));
    assert.match(await readFile(join(installed, 'Contents/Info.plist'), 'utf8'), /0\.1\.0/);
    await updater.setAutomatic(false);
    const reopened = createUpdater(options);
    await reopened.initialize();
    assert.equal(reopened.state.automatic, false);
    assert.equal(reopened.state.ready, true);
    assert.equal(await reopened.installPrepared(), null);
    await reopened.setAutomatic(true);
    const child = await reopened.installPrepared({ waitPID: 2147483647, relaunch: false });
    child.ref();
    const [code] = await once(child, 'exit');
    assert.equal(code, 0, await readFile(join(root, 'cache/install.log'), 'utf8'));
    assert.match(await readFile(join(installed, 'Contents/Info.plist'), 'utf8'), /0\.1\.1/);
    assert.match(await readFile(join(root, 'installed/.Konglish-previous.app/Contents/Info.plist'), 'utf8'), /0\.1\.0/);
    await assert.rejects(access(join(root, 'cache/pending.json')));
    await assert.rejects(access(join(root, 'cache', pending.directory)));
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('a mismatched download checksum cannot become an installable update', { skip: process.platform !== 'darwin' }, async () => {
  const scratch = resolve('work/disposable');
  await mkdir(scratch, { recursive: true });
  const root = await mkdtemp(join(scratch, 'test-updates-'));
  try {
    const installed = join(root, 'Konglish.app');
    await fixtureApp(installed, '0.1.0');
    const updater = createUpdater({ version: '0.1.0', arch: 'arm64', cacheDir: join(root, 'cache'), installPath: installed,
      fetchImpl: async url => new Response(url.endsWith('/latest') ? JSON.stringify(release(Buffer.from('good'))) : Buffer.from('evil')) });
    await updater.initialize();
    await updater.check();
    assert.equal(updater.state.ready, false);
    assert.match(updater.state.text, /검증/);
    await assert.rejects(access(join(root, 'cache/pending.json')));
    assert.equal(await updater.installPrepared(), null);
  } finally { await rm(root, { recursive: true, force: true }); }
});
