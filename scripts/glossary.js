import { readFileSync, writeFileSync } from 'node:fs';

const entries = JSON.parse(readFileSync(new URL('../glossary.json', import.meta.url), 'utf8'));
const target = new URL('../addon/Konglish/Glossary.lua', import.meta.url);
const quote = value => JSON.stringify(value);
const lines = Object.entries(entries).map(([source, target]) => `    [${quote(source)}] = ${quote(target)},`);
const lua = ['-- Generated from glossary.json by scripts/glossary.js.', 'local _, Konglish = ...',
  'Konglish.glossary = {', ...lines, '}', ''].join('\n');

if (process.argv.includes('--check')) {
  if (readFileSync(target, 'utf8') !== lua) {
    throw new Error('Glossary.lua is out of date. Run node scripts/glossary.js.');
  }
} else {
  writeFileSync(target, lua);
}
