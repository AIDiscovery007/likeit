import assert from 'node:assert/strict';
import { mkdir, writeFile, chmod } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { openNetease } from './src/netease.ts';

const root = fileURLToPath(new URL('.', import.meta.url));
const results = [];
const ready = `process.stdout.write('{"ready":true}\\n');`;
const cases = [
  ['startup-timeout', 'setInterval(() => {}, 1000);', 'open', /Native request timed out/, 1800, 4000],
  ['request-timeout', ready + 'process.stdin.resume();setInterval(() => {}, 1000);', 'read', /Native request timed out/, 8500, 11000],
  ['malformed-response', ready + `process.stdin.once('data', () => process.stdout.write('invalid\\n'));`, 'read', /Invalid native response/, 0, 2500],
  ['oversize-response', ready + `process.stdin.once('data', () => process.stdout.write('x'.repeat(70000)));`, 'read', /Native response exceeded limit/, 0, 2500],
  ['invalid-snapshot', ready + `process.stdin.once('data', () => process.stdout.write('{"snapshot":{"state":"playing","trackKey":false,"liked":false}}\\n'));`, 'read', /Invalid native snapshot/, 0, 2500],
  ['close-grace-timeout', ready + 'process.stdin.resume();setInterval(() => {}, 1000);', 'close', null, 450, 2000],
];
for (const [name, body, action, error, minMs, maxMs] of cases) {
  const directory = join(root, 'review-scratch/protocol-' + name);
  await mkdir(directory, { recursive: true });
  const executable = join(directory, 'likeit-controller');
  await writeFile(executable, '#!' + process.execPath + '\n' + body);
  await chmod(executable, 0o755);
  const start = Date.now();
  if (action === 'open') await assert.rejects(openNetease(directory, directory), error);
  else {
    const session = await openNetease(directory, directory);
    try { if (action === 'read') await assert.rejects(session.port.read(), error); }
    finally { await session.close(); }
  }
  const elapsedMs = Date.now() - start;
  assert.ok(elapsedMs >= minMs && elapsedMs < maxMs, `${name}: ${elapsedMs}`);
  const result = { name, pass: true, elapsedMs };
  results.push(result); console.log(JSON.stringify(result));
}
await writeFile(join(root, 'review-scratch/protocol-results.json'), JSON.stringify(results, null, 2));
