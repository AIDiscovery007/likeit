import assert from "node:assert/strict";
import test from "node:test";
import { readFile } from "node:fs/promises";
import { presentResult } from "../src/result-feedback.ts";

function feedback(policy, animation) {
  const calls = [];
  return { calls, port: {
    async showHUD(status) { calls.push(["hud", status]); },
    async readReduceMotion() { calls.push(["motion"]); if (policy instanceof Error) throw policy; return policy; },
    async celebrate(mode) { calls.push(["celebrate", mode]); if (animation) await animation(); },
  }};
}

test("M01: one independent three-mode preference defaults to following system", async () => {
  const manifest = JSON.parse(await readFile(new URL("../package.json", import.meta.url), "utf8"));
  const preference = manifest.preferences.find((item) => item.name === "motionMode");
  assert.ok(preference);
  assert.equal(preference.type, "dropdown");
  assert.equal(preference.title, "收藏成功动效");
  assert.equal(preference.default, "system");
  assert.deepEqual(preference.data, [
    { title: "跟随系统", value: "system" },
    { title: "始终播放", value: "always" },
    { title: "关闭", value: "off" },
  ]);
  assert.equal(manifest.preferences.some((item) => item.name === "successConfetti"), false);
});

for (const policy of [false, true, undefined, null, new Error("unavailable")]) {
  test(`M02: system honors strict motion policy ${String(policy)}`, async () => {
    const { calls, port } = feedback(policy);
    await presentResult("liked", "system", port);
    assert.deepEqual(calls, [["hud", "liked"], ["motion"], ...(policy === false ? [["celebrate", "system"]] : [])]);
  });
}

test("M03: always does not depend on system preference and passes explicit permission", async () => {
  const { calls, port } = feedback(new Error("must not read system"));
  await presentResult("liked", "always", port);
  assert.deepEqual(calls, [["hud", "liked"], ["celebrate", "always"]]);
});

for (const mode of ["off", undefined, null, "invalid", "ALWAYS", "", 1, {}, []]) {
  test(`M04: off or invalid mode ${String(mode)} preserves HUD without optional work`, async () => {
    const { calls, port } = feedback();
    await presentResult("liked", mode, port);
    assert.deepEqual(calls, [["hud", "liked"]]);
  });
}

for (const mode of ["system", "always", "off"]) {
  test(`M05: ${mode} never celebrates any non-confirmed result`, async () => {
    for (const status of ["already-liked", "not-running", "not-playing", "unavailable", "permission-required", "track-changed", "unconfirmed", "failed", "busy"]) {
      const { calls, port } = feedback();
      await presentResult(status, mode, port);
      assert.deepEqual(calls, [["hud", status]], status);
    }
  });
}

for (const mode of ["system", "always"]) {
  test(`M06: ${mode} animation failure keeps successful HUD and never retries`, async () => {
    const { calls, port } = feedback(false, async () => { throw new Error("renderer"); });
    await assert.doesNotReject(presentResult("liked", mode, port));
    assert.deepEqual(calls, [["hud", "liked"], ...(mode === "system" ? [["motion"]] : []), ["celebrate", mode]]);
  });
}

test("M07: legacy true still follows system and legacy false stays off", async () => {
  for (const enabled of [true, false]) {
    const { calls, port } = feedback(false);
    await presentResult("liked", enabled, port);
    assert.deepEqual(calls, [["hud", "liked"], ...(enabled ? [["motion"], ["celebrate", "system"]] : [])]);
  }
});
