import { createInterface } from 'node:readline';

function emit(event) { process.stdout.write(JSON.stringify(event) + '\n'); }

emit({ kind: 'foreground', text: 'wow' });
emit({ kind: 'translate', id: 2, text: 'must stay in the native overlay' });
emit({ kind: 'status', text: 'fixture ready' });
createInterface({ input: process.stdin }).on('line', line => emit({ kind: 'status', text: line }));
