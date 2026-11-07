import { execFileSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = new URL('../', import.meta.url);
const path = file => fileURLToPath(new URL(file, root));
mkdirSync(path('.build/'), { recursive: true });
const binary = path('.build/overlay-checks');
execFileSync('xcrun', ['swiftc', path('desktop/native/OverlayModel.swift'), path('desktop/native/ChatMotion.swift'), path('test/OverlayChecks.swift'), '-o', binary],
  { stdio: 'inherit' });
execFileSync(binary, { stdio: 'inherit' });
const draftBinary = path('.build/draft-input-checks');
execFileSync('xcrun', ['swiftc', path('desktop/native/DraftInput.swift'), path('test/DraftInputChecks.swift'), '-o', draftBinary],
  { stdio: 'inherit' });
execFileSync(draftBinary, { stdio: 'inherit' });
