import { createReadStream, createWriteStream } from 'node:fs';
import { access, chmod, lstat, mkdir, mkdtemp, readFile, readdir, realpath, rename, rm, statfs, writeFile } from 'node:fs/promises';
import { constants } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFile, spawn } from 'node:child_process';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { Readable, Transform } from 'node:stream';
import { pipeline } from 'node:stream/promises';

const run = promisify(execFile);
const repository = 'CodeNyangi/wowforever-konglish';
const releaseAPI = `https://api.github.com/repos/${repository}/releases/latest`;
const bundleID = 'com.wowforever.konglish';
const maxDownload = 350 * 1024 * 1024;
const installer = fileURLToPath(new URL('./install-update.sh', import.meta.url));

function versionParts(value) {
  return /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(value ?? '') ? value.split('.').map(Number) : null;
}

export function selectUpdate(release, current, arch) {
  const version = release?.tag_name?.replace(/^v/, '');
  const next = versionParts(version);
  const previous = versionParts(current);
  if (!next || !previous || release.draft || release.prerelease) return null;
  const difference = next.map((part, i) => part - previous[i]).find(value => value !== 0) ?? 0;
  if (difference <= 0 || !['arm64', 'x64'].includes(arch)) return null;
  const name = `Konglish-${version}-mac-${arch}.zip`;
  const url = `https://github.com/${repository}/releases/download/v${version}/${name}`;
  const asset = release.assets?.find(item => item.name === name && item.state === 'uploaded');
  if (!asset || asset.browser_download_url !== url || !/^sha256:[a-f0-9]{64}$/.test(asset.digest ?? '') ||
      !Number.isSafeInteger(asset.size) || asset.size <= 0 || asset.size > maxDownload) return null;
  return { version, url, digest: asset.digest.slice(7), size: asset.size };
}

async function sha256(path) {
  const hash = createHash('sha256');
  for await (const bytes of createReadStream(path)) hash.update(bytes);
  return hash.digest('hex');
}

async function plist(appPath, key) {
  return (await run('/usr/libexec/PlistBuddy', ['-c', `Print :${key}`, join(appPath, 'Contents/Info.plist')])).stdout.trim();
}

async function validateBundle(path, version) {
  if ((await lstat(path)).isSymbolicLink() || await plist(path, 'CFBundleIdentifier') !== bundleID ||
      await plist(path, 'CFBundleShortVersionString') !== version || await plist(path, 'CFBundleVersion') !== version ||
      await plist(path, 'CFBundleExecutable') !== 'Konglish') throw new Error('잘못된 앱 파일이에요.');
  await run('/usr/bin/codesign', ['--verify', '--deep', '--strict', path]);
  const root = await realpath(path);
  async function walk(directory) {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      const child = join(directory, entry.name);
      if (entry.isSymbolicLink()) {
        const resolved = await realpath(child);
        if (resolved !== root && !resolved.startsWith(root + sep)) throw new Error('앱 밖을 가리키는 파일이에요.');
      } else if (entry.isDirectory()) await walk(child);
    }
  }
  await walk(path);
}

export function createUpdater({ version, arch = process.arch, cacheDir, installPath, onStatus = () => {}, fetchImpl = fetch }) {
  const pendingFile = join(cacheDir, 'pending.json');
  const preferenceFile = join(cacheDir, 'preferences.json');
  let automatic = true;
  let checking;
  let prepared;
  let state = { text: '자동 업데이트', automatic: true, ready: false };

  function status(text) {
    state = { text, automatic, ready: Boolean(prepared) };
    onStatus(state);
  }

  async function readPending() {
    try {
      const value = JSON.parse(await readFile(pendingFile, 'utf8'));
      if (!versionParts(value.version) || !/^sha256:[a-f0-9]{64}$/.test(value.digest) ||
          !/^update-[a-zA-Z0-9]+$/.test(value.directory) || !selectUpdate({
            tag_name: `v${value.version}`, assets: [{ name: `Konglish-${value.version}-mac-${arch}.zip`, state: 'uploaded',
              size: 1, digest: value.digest,
              browser_download_url: `https://github.com/${repository}/releases/download/v${value.version}/Konglish-${value.version}-mac-${arch}.zip` }],
          }, version, arch)) return null;
      const directory = join(cacheDir, value.directory);
      if ((await sha256(join(directory, 'download.zip'))) !== value.digest.slice(7)) return null;
      const source = join(directory, 'Konglish.app');
      await validateBundle(source, value.version);
      return { ...value, source };
    } catch { return null; }
  }

  async function initialize() {
    await mkdir(cacheDir, { recursive: true, mode: 0o700 });
    await chmod(cacheDir, 0o700);
    try { automatic = JSON.parse(await readFile(preferenceFile, 'utf8')).automatic !== false; } catch {}
    prepared = await readPending();
    let pendingDirectory;
    try { pendingDirectory = JSON.parse(await readFile(pendingFile, 'utf8')).directory; } catch {}
    for (const entry of await readdir(cacheDir, { withFileTypes: true })) {
      if (entry.isDirectory() && /^update-[a-zA-Z0-9]+$/.test(entry.name) && entry.name !== pendingDirectory) {
        await rm(join(cacheDir, entry.name), { recursive: true, force: true });
      }
    }
    // A pending update is kept when automatic updates are switched off.
    status(prepared ? '업데이트 준비됨 · 다음 실행 때 적용' : automatic ? '자동 업데이트' : '자동 업데이트 꺼짐');
    return { ...state };
  }

  async function setAutomatic(value) {
    automatic = Boolean(value);
    await writeFile(preferenceFile, JSON.stringify({ automatic }), { mode: 0o600 });
    status(prepared ? '업데이트 준비됨 · 다음 실행 때 적용' : automatic ? '자동 업데이트' : '자동 업데이트 꺼짐');
  }

  async function check() {
    if (checking) return checking;
    checking = (async () => {
      if (prepared) { status('업데이트 준비됨 · 다음 실행 때 적용'); return; }
      let directory;
      try {
        status('업데이트 확인 중…');
        const response = await fetchImpl(releaseAPI, {
          headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'Konglish-Updater' },
          signal: AbortSignal.timeout(15000),
        });
        if (!response.ok) throw new Error('업데이트 서버에 연결하지 못했어요.');
        const candidate = selectUpdate(await response.json(), version, arch);
        if (!candidate) { status('최신 버전'); return; }
        await access(dirname(installPath), constants.W_OK);
        if (await plist(installPath, 'CFBundleIdentifier') !== bundleID) throw new Error('설치 위치를 확인해 주세요.');
        const disk = await statfs(cacheDir);
        if (Number(disk.bavail) * Number(disk.bsize) < 2 * 1024 ** 3) throw new Error('업데이트할 여유 공간이 부족해요.');
        directory = await mkdtemp(join(cacheDir, 'update-'));
        const archive = join(directory, 'download.zip');
        status(`v${candidate.version} 받는 중…`);
        const download = await fetchImpl(candidate.url, { signal: AbortSignal.timeout(10 * 60 * 1000) });
        if (!download.ok || !download.body) throw new Error('업데이트를 받지 못했어요.');
        let bytes = 0;
        const sizeLimit = new Transform({ transform(chunk, _, callback) {
          bytes += chunk.length;
          callback(bytes > candidate.size || bytes > maxDownload ? new Error('파일 크기가 달라요.') : null, chunk);
        } });
        await pipeline(Readable.fromWeb(download.body), sizeLimit, createWriteStream(archive, { flags: 'wx', mode: 0o600 }));
        if (bytes !== candidate.size || await sha256(archive) !== candidate.digest) throw new Error('파일 검증에 실패했어요.');
        const listing = (await run('/usr/bin/unzip', ['-Z1', archive], { maxBuffer: 4 * 1024 * 1024 })).stdout.trim().split('\n');
        if (!listing.length || listing.some(path => path.startsWith('/') || path.includes('\\') || path.split('/').includes('..') ||
            !['Konglish.app', '__MACOSX'].includes(path.split('/')[0]))) throw new Error('잘못된 압축 파일이에요.');
        await run('/usr/bin/ditto', ['-x', '-k', archive, directory]);
        await validateBundle(join(directory, 'Konglish.app'), candidate.version);
        const pending = { version: candidate.version, digest: `sha256:${candidate.digest}`, directory: relative(cacheDir, directory) };
        const temporary = pendingFile + '.tmp';
        await writeFile(temporary, JSON.stringify(pending), { mode: 0o600 });
        await rename(temporary, pendingFile);
        prepared = { ...pending, source: join(directory, 'Konglish.app') };
        directory = undefined;
        status('업데이트 준비됨 · 다음 실행 때 적용');
      } catch (error) {
        status(`${error.message} 메뉴에서 다시 확인할 수 있어요.`);
      } finally {
        if (directory) await rm(directory, { recursive: true, force: true });
      }
    })();
    try { await checking; } finally { checking = undefined; }
  }

  async function installPrepared({ relaunch = true, waitPID = process.pid } = {}) {
    if (!automatic || !prepared) return null;
    const verified = await readPending();
    if (!verified) { prepared = undefined; status('업데이트 파일을 다시 받아야 해요.'); return null; }
    const child = spawn('/bin/sh', [installer, String(waitPID), verified.source, resolve(installPath),
      verified.version, cacheDir, relaunch ? '1' : '0'], { detached: true, stdio: 'ignore' });
    child.on('error', () => status('업데이트 설치를 시작하지 못했어요.'));
    child.unref();
    return child;
  }

  return { initialize, check, setAutomatic, installPrepared, get state() { return { ...state }; } };
}
