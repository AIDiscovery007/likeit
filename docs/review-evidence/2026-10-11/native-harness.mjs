import assert from 'node:assert/strict';
import { spawn, execFileSync } from 'node:child_process';
import { cp, mkdir, writeFile, readFile, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { openNetease, BusyError } from './src/netease.ts';

const root = fileURLToPath(new URL('.', import.meta.url));
const native = join(root, 'assets/native');
const scratch = join(root, 'review-scratch');
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const results = [];
await mkdir(scratch, { recursive: true });
function record(name, evidence) { results.push({ name, pass: true, evidence }); console.log(JSON.stringify(results.at(-1))); }
function alive(pid) {
  try { return !execFileSync('/bin/ps', ['-o', 'stat=', '-p', String(pid)], { encoding: 'utf8' }).trim().startsWith('Z'); }
  catch { return false; }
}
async function until(check, timeout = 3000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) { const value = await check(); if (value) return value; await sleep(25); }
  throw new Error('Condition did not become true');
}
async function fixture(name, body) {
  const directory = join(scratch, name);
  await mkdir(directory, { recursive: true });
  await cp(join(native, 'likeit-controller'), join(directory, 'likeit-controller'));
  await writeFile(join(directory, 'mediaremote-adapter.pl'), 'use strict; use warnings;\n' + body);
  return directory;
}
async function recover(support) { const s = await openNetease(native, support); await s.close(); }

try {
  const support = join(scratch, 'real-lock');
  const one = await openNetease(native, support);
  try {
    const inode = (await stat(join(support, 'netease.lock'))).ino;
    await assert.rejects(openNetease(native, support), BusyError);
    const snapshot = await one.port.read();
    await writeFile(join(scratch, 'real-read.json'), JSON.stringify(snapshot, null, 2));
    assert.ok(['playing', 'paused'].includes(snapshot.state), 'Real snapshot must prove the native media path was reached');
    record('native read and exclusive busy lock', { state: snapshot.state, title: snapshot.title, liked: snapshot.liked });
    await one.close();
    await recover(support);
    assert.equal((await stat(join(support, 'netease.lock'))).ino, inode);
    record('normal close releases same lock inode', { inode });
  } finally { await one.close(); }

  for (const [name, body, minMs, maxMs] of [
    ['media-timeout', 'sleep 30; print "null";', 3500, 6500],
    ['output-limit', 'print "x" x 70000;', 0, 3000],
    ['invalid-json', 'print "not-json";', 0, 3000],
    ['nonzero-exit', 'exit 7;', 0, 3000],
  ]) {
    const directory = await fixture(name, body);
    const support = join(scratch, name + '-lock');
    const session = await openNetease(directory, support);
    const start = Date.now();
    try { await assert.rejects(session.port.read(), /Native operation failed/); }
    finally { await session.close(); }
    const elapsed = Date.now() - start;
    assert.ok(elapsed >= minMs && elapsed < maxMs, `${name}: unexpected duration ${elapsed}`);
    await recover(support);
    record(name, { elapsedMs: elapsed, lockRecovered: true });
  }

  const workerPath = join(scratch, 'worker.mjs');
  await writeFile(workerPath, `import { openNetease } from ${JSON.stringify(new URL('./src/netease.ts', import.meta.url).href)};\nconst s = await openNetease(process.argv[2], process.argv[3]);\nconsole.log('READY');\ns.port.read().then(x => console.log(JSON.stringify(x)), e => console.log(e.message));\nsetInterval(() => {}, 1000);\n`);
  for (const target of ['controller', 'node-parent']) {
    const directory = await fixture('kill-' + target, 'open(my $f, ">", $ENV{LIKEIT_REVIEW_PIDLOG}) or die $!; print $f join(" ", $$, getppid(), getpgrp(0)); close($f); sleep 30; print "null";');
    const support = join(scratch, 'kill-' + target + '-lock');
    const pidlog = join(directory, 'pids.txt');
    const worker = spawn(process.execPath, [workerPath, directory, support], { env: { ...process.env, LIKEIT_REVIEW_PIDLOG: pidlog }, stdio: ['ignore', 'pipe', 'pipe'] });
    let workerOutput = '';
    worker.stdout.on('data', (s) => workerOutput += s);
    worker.stderr.on('data', () => {});
    let perl, controller;
    try {
      const text = await until(async () => { try { return await readFile(pidlog, 'utf8'); } catch { return false; } });
      const values = text.trim().split(' ').map(Number);
      [perl, controller] = values;
      assert.equal(values[2], controller, 'Perl must inherit controller PGID');
      const pidsBefore = execFileSync('/bin/ps', ['-o', 'pid=,ppid=,pgid=,stat=', '-p', [worker.pid, controller, perl].join(',')], { encoding: 'utf8' }).trim();
      process.kill(target === 'controller' ? controller : worker.pid, 'SIGKILL');
      await until(() => !alive(controller) && !alive(perl));
      await recover(support);
      record('SIGKILL ' + target, { pidsBefore, controllerAndPerlGone: true, lockRecovered: true, workerOutput });
    } finally {
      worker.kill('SIGKILL');
      for (const pid of [controller, perl]) if (pid) { try { process.kill(pid, 'SIGKILL'); } catch {} }
    }
  }
  await writeFile(join(scratch, 'results.json'), JSON.stringify(results, null, 2));
} catch (error) {
  console.error(error);
  await writeFile(join(scratch, 'results.json'), JSON.stringify({ results, error: String(error) }, null, 2));
  process.exitCode = 1;
}
