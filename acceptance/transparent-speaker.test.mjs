import assert from "node:assert/strict";
import test from "node:test";
import { execFile } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const exec = promisify(execFile);
const root = fileURLToPath(new URL("../", import.meta.url));

// Reviewer-owned: real production model, isolated defaults, no music or capture access.
test("T01–T05: theme selection preserves the current desktop and survives restart", { timeout: 120000 }, async t => {
  const directory = await mkdtemp(join(tmpdir(), "likeit-theme-bdd-"));
  const binary = join(directory, "acceptance");
  const suite = `com.likeit.acceptance.theme.${randomUUID()}`;
  let compiled = false;
  try {
    await exec("xcrun", ["swiftc", "native/ImmersiveCore.swift", "native/DesktopCommunityLyricsCore.swift", "native/DesktopView.swift", "acceptance/transparent-speaker-driver.swift", "-o", binary], { cwd: root, timeout: 90000, maxBuffer: 1024 * 1024 });
    compiled = true;
    const { stdout } = await exec(binary, [suite, "scenarios"], { timeout: 10000 });
    const results = JSON.parse(stdout);
    assert.equal(Object.keys(results).length, 20, "all frozen state scenarios must report");
    for (const [name, passed] of Object.entries(results)) await t.test(name, () => assert.equal(passed, true));
    await exec(binary, [suite, "write"], { timeout: 10000 });
    const reopened = await exec(binary, [suite, "read"], { timeout: 10000 });
    await t.test("T02/T04: a separate process restores theme and scene", () => assert.equal(reopened.stdout.trim(), "glass/paper"));
  } finally {
    if (compiled) await exec(binary, [suite, "cleanup"], { timeout: 10000 });
    await rm(directory, { recursive: true, force: true });
  }
});
