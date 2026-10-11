import assert from "node:assert/strict";
import test from "node:test";
import { readFile, mkdtemp, rm } from "node:fs/promises";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
const exec = promisify(execFile);
const root = fileURLToPath(new URL("../", import.meta.url));

// Reviewer-owned: synthetic text and PCM only; never touches music apps or capture permissions.
test("I01: Likeit menu supplements the original one-action like command", async () => {
  const manifest = JSON.parse(await readFile(join(root, "package.json"), "utf8"));
  const menu = manifest.commands.find(c => c.name === "music-desktop");
  assert.ok(menu, "music-desktop menu missing");
  assert.equal(menu.mode, "view");
  assert.equal(menu.title, "Likeit");
  const like = manifest.commands.find(c => c.name === "likeit");
  assert.equal(like.mode, "no-view");
  assert.ok(like.keywords.includes("like"));
});

test("I11: desktop motion is an independent three-mode preference", async () => {
  const manifest = JSON.parse(await readFile(join(root, "package.json"), "utf8"));
  const preference = manifest.preferences.find(p => p.name === "desktopMotionMode");
  assert.ok(preference, "desktop motion preference missing");
  assert.equal(preference.type, "dropdown");
  assert.equal(preference.title, "沉浸桌面动效");
  assert.equal(preference.default, "system");
  assert.deepEqual(preference.data, [
    { title: "跟随系统", value: "system" },
    { title: "始终播放", value: "always" },
    { title: "关闭", value: "off" },
  ]);
  assert.equal(manifest.preferences.find(p => p.name === "motionMode").title, "收藏成功动效");
});

test("I04–I11: production native core satisfies frozen behavior scenarios", { timeout: 120000 }, async t => {
  const directory = await mkdtemp(join(tmpdir(), "likeit-immersive-bdd-"));
  try {
    await exec("xcrun", ["swiftc", "-O", join(root, "native/ImmersiveCore.swift"), join(root, "acceptance/immersive-core-driver.swift"), "-framework", "Accelerate", "-o", join(directory, "bdd")], { timeout: 90000, maxBuffer: 512 * 1024 });
    const { stdout } = await exec(join(directory, "bdd"), [], { timeout: 10000, maxBuffer: 512 * 1024 });
    const results = JSON.parse(stdout);
    assert.equal(results.length, 54, "all pre-frozen scenarios must report");
    for (const result of results) await t.test(result.name, () => assert.equal(result.passed, true));
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
