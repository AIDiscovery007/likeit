import assert from "node:assert/strict";
import test from "node:test";
import { likeCurrentTrack } from "../src/like-current-track.ts";

const song = (changes = {}) => ({ state: "playing", trackKey: "netease:A", liked: false, title: "Song A", ...changes });
function player(readings, action = "pressed") {
  let index = 0;
  const writes = [];
  return {
    writes,
    async read() {
      const value = readings[Math.min(index++, readings.length - 1)];
      if (value instanceof Error) throw value;
      return { ...value };
    },
    async pressLike(key) {
      writes.push(key);
      if (action instanceof Error) throw action;
      return action;
    },
  };
}

test("A01: confirms the same track is liked after exactly one write", async () => {
  const port = player([song(), song(), song({ liked: true })]);
  assert.equal((await likeCurrentTrack(port)).status, "liked");
  assert.deepEqual(port.writes, ["netease:A"]);
});

test("A02: an already-liked track is never toggled", async () => {
  const port = player([song({ liked: true })]);
  assert.equal((await likeCurrentTrack(port)).status, "already-liked");
  assert.deepEqual(port.writes, []);
});

for (const [label, snapshot, expected] of [
  ["not running", song({ state: "not-running", trackKey: null }), "not-running"],
  ["paused with a residual track", song({ state: "paused" }), "not-playing"],
  ["unknown playback", song({ state: "unknown" }), "unavailable"],
  ["unknown like state", song({ liked: null }), "unavailable"],
  ["missing track identity", song({ trackKey: null }), "unavailable"],
  ["empty track identity", song({ trackKey: "" }), "unavailable"],
  ["missing permission", song({ state: "permission-required" }), "permission-required"],
]) {
  test(`A03: ${label} causes no write`, async () => {
    const port = player([snapshot]);
    assert.equal((await likeCurrentTrack(port)).status, expected);
    assert.deepEqual(port.writes, []);
  });
}

for (const [label, snapshot, expected] of [
  ["track changed", song({ trackKey: "netease:B" }), "track-changed"],
  ["track paused", song({ state: "paused" }), "not-playing"],
  ["app quit", song({ state: "not-running" }), "not-running"],
  ["liked elsewhere", song({ liked: true }), "already-liked"],
  ["identity became unavailable", song({ trackKey: null }), "unavailable"],
  ["like state became unavailable", song({ liked: null }), "unavailable"],
  ["permission revoked", song({ state: "permission-required" }), "permission-required"],
]) {
  test(`A04: recheck detects that ${label}`, async () => {
    const port = player([song(), snapshot]);
    assert.equal((await likeCurrentTrack(port)).status, expected);
    assert.deepEqual(port.writes, []);
  });
}

for (const [action, expected] of [
  ["changed", "track-changed"],
  ["already-liked", "already-liked"],
  ["unavailable", "unavailable"],
]) {
  test(`A05: native guard returning ${action} is respected without retries`, async () => {
    const port = player([song()], action);
    assert.equal((await likeCurrentTrack(port)).status, expected);
    assert.deepEqual(port.writes, ["netease:A"]);
  });
}

for (const [label, after] of [
  ["the track changed even though the new one is liked", song({ trackKey: "netease:B", liked: true })],
  ["the like state never changed", song()],
  ["the identity disappeared", song({ trackKey: null, liked: true })],
  ["the like state is unknown", song({ liked: null })],
  ["the app disappeared", song({ state: "not-running" })],
  ["confirmation cannot be read", new Error("read failed")],
]) {
  test(`A06: ${label} cannot produce success`, async () => {
    const port = player([song(), song(), after]);
    assert.equal((await likeCurrentTrack(port)).status, "unconfirmed");
    assert.deepEqual(port.writes, ["netease:A"]);
  });
}

test("A06: an uncertain write is never retried", async () => {
  const port = player([song()], new Error("write response lost"));
  assert.equal((await likeCurrentTrack(port)).status, "unconfirmed");
  assert.deepEqual(port.writes, ["netease:A"]);
});

for (const readings of [[new Error("read failed")], [song(), new Error("recheck failed")]]) {
  test(`A10: read failure before mutation (${readings.length}) is reported without writing`, async () => {
    const port = player(readings);
    assert.equal((await likeCurrentTrack(port)).status, "failed");
    assert.deepEqual(port.writes, []);
  });
}
