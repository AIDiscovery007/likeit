import assert from "node:assert/strict";
import test from "node:test";
import { presentResult } from "../src/result-feedback.ts";

function feedback(overrides = {}) {
  const calls = [];
  return {
    calls,
    port: {
      async showHUD(status) { calls.push(["hud", status]); },
      async readReduceMotion() { calls.push(["motion"]); return false; },
      async celebrate() { calls.push(["celebrate"]); },
      ...overrides,
    },
  };
}

test("C01: confirmed new favorite shows its HUD before one celebration", async () => {
  const { calls, port } = feedback();
  await presentResult("liked", true, port);
  assert.deepEqual(calls, [["hud", "liked"], ["motion"], ["celebrate"]]);
});

for (const status of ["already-liked", "not-running", "not-playing", "unavailable", "permission-required", "track-changed", "unconfirmed", "failed", "busy"]) {
  test(`C02: ${status} retains its feedback without checking or starting animation`, async () => {
    const { calls, port } = feedback();
    await presentResult(status, true, port);
    assert.deepEqual(calls, [["hud", status]]);
  });
}

test("C03: disabling celebration preserves successful favorite feedback", async () => {
  const { calls, port } = feedback();
  await presentResult("liked", false, port);
  assert.deepEqual(calls, [["hud", "liked"]]);
});

for (const value of [true, undefined, null]) {
  test(`C04: reduced motion or unreadable policy (${value}) suppresses celebration`, async () => {
    const { calls, port } = feedback({ async readReduceMotion() { calls.push(["motion"]); return value; } });
    await presentResult("liked", true, port);
    assert.deepEqual(calls, [["hud", "liked"], ["motion"]]);
  });
}

test("C04: motion policy read failure preserves success and does not launch", async () => {
  const { calls, port } = feedback({ async readReduceMotion() { throw new Error("policy unavailable"); } });
  await assert.doesNotReject(presentResult("liked", true, port));
  assert.deepEqual(calls, [["hud", "liked"]]);
});

for (const synchronous of [true, false]) {
  test(`C05: animation ${synchronous ? "throw" : "rejection"} cannot replace success or retry`, async () => {
    const { calls, port } = feedback({
      celebrate() {
        calls.push(["celebrate"]);
        if (synchronous) throw new Error("renderer missing");
        return Promise.reject(new Error("renderer failed"));
      },
    });
    await assert.doesNotReject(presentResult("liked", true, port));
    await new Promise((resolve) => setImmediate(resolve));
    assert.deepEqual(calls, [["hud", "liked"], ["motion"], ["celebrate"]]);
  });
}

test("C05: slow animation startup cannot delay the already determined HUD", async () => {
  let release;
  const pending = new Promise((resolve) => { release = resolve; });
  const { calls, port } = feedback({ async celebrate() { calls.push(["celebrate"]); await pending; } });
  const presenting = presentResult("liked", true, port);
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(calls, [["hud", "liked"], ["motion"], ["celebrate"]]);
  release();
  await presenting;
});
