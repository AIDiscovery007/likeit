import assert from "node:assert/strict";
import { test } from "node:test";
import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

test("visible desktop capture is independent of application focus", { timeout: 30000 }, async (t) => {
  const source = readFileSync("native/DesktopMain.swift", "utf8");
  const methods = [...source.matchAll(/^    private func updateMotion\(\) \{[\s\S]*?^    \}/gm)];
  assert.equal(methods.length, 1, "Exercise the real delegate decision exactly once");
  const folder = mkdtempSync(join(tmpdir(), "likeit-visibility-"));
  try {
    const driver = join(folder, "driver.swift"), binary = join(folder, "driver");
    // Copy the production method byte-for-byte; only its OS inputs and output sinks are fixtures.
    writeFileSync(driver, readFileSync("acceptance/immersive-visibility-driver.swift", "utf8").replace("    // PRODUCTION_UPDATE_MOTION", methods[0][0]));
    const build = spawnSync("xcrun", ["swiftc", "-O", "-parse-as-library", "native/ImmersiveCore.swift", driver, "-o", binary], { encoding: "utf8", timeout: 20000 });
    assert.equal(build.status, 0, build.stderr);
    const run = spawnSync(binary, { encoding: "utf8", timeout: 3000 });
    assert.equal(run.signal, null, run.stderr);
    const results = JSON.parse(run.stdout);
    assert.equal(results.length, 14);
    for (const result of results) await t.test(result.case, () => assert.equal(result.passed, true));
    assert.equal(run.status, 0, run.stderr);
  } finally {
    rmSync(folder, { recursive: true, force: true });
  }
});
