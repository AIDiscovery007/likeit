import assert from 'node:assert/strict';
import { test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// Compile unmodified production capture code against the coordinator's HAL fixtures.
// Refuse to execute if even one real HAL function remains linked.
test('audio interruption recovers without blaming permission or reopening', { timeout: 30000 }, async (t) => {
  const folder = mkdtempSync(join(tmpdir(), 'likeit-audio-acceptance-'));
  try {
    const binary = join(folder, 'driver');
    const build = spawnSync('xcrun', ['swiftc', '-O', '-parse-as-library', 'native/DesktopAudio.swift', 'native/ImmersiveCore.swift', 'acceptance/immersive-audio-interruption-driver.swift', '-o', binary], { encoding: 'utf8', timeout: 20000 });
    assert.equal(build.status, 0, build.stderr);
    const symbols = spawnSync('nm', ['-u', binary], { encoding: 'utf8', timeout: 2000 });
    assert.equal(symbols.status, 0, symbols.stderr);
    assert.doesNotMatch(symbols.stdout, /_(AudioObject|AudioDevice|AudioHardware)/, 'Fixture binary must never invoke real HAL functions');
    const run = spawnSync(binary, { encoding: 'utf8', timeout: 15000 });
    assert.equal(run.signal, null, run.stderr);
    const results = JSON.parse(run.stdout);
    assert.equal(results.length, 21);
    for (const result of results) await t.test(result.case, () => assert.equal(result.passed, true));
    assert.equal(run.status, 0, run.stderr);
  } finally {
    rmSync(folder, { recursive: true, force: true });
  }
});
