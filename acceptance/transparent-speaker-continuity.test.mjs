import assert from "node:assert/strict";
import test from "node:test";
import { execFile } from "node:child_process";
import { readFile, writeFile, mkdtemp, rm } from "node:fs/promises";
import { promisify } from "node:util";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const exec = promisify(execFile);
const root = fileURLToPath(new URL("../", import.meta.url));
function one(source, pattern, name) {
  const matches = [...source.matchAll(pattern)];
  assert.equal(matches.length, 1, `Inspect the production ${name} boundary if its declaration changes`);
  return matches[0][0];
}

// Execute production receive and Session methods. Only layout storage and OS sinks are fixtures.
test("lyric continuity uses source samples instead of View observation timing", { timeout: 120000 }, async t => {
  const [session, media, view, fixture, checks] = await Promise.all([
    readFile(join(root, "native/DesktopSession.swift"), "utf8"),
    readFile(join(root, "native/DesktopMedia.swift"), "utf8"),
    readFile(join(root, "native/DesktopView.swift"), "utf8"),
    readFile(join(root, "acceptance/transparent-speaker-motion-driver.swift"), "utf8"),
    readFile(join(root, "acceptance/transparent-speaker-continuity-driver.swift"), "utf8"),
  ]);
  const methods = ["resetLyrics", "clearDisplayedLyrics", "renderCommunity", "render", "clear", "stop"].map(name =>
    one(session, new RegExp(`^    (?:private )?func ${name}\\([^\\n]*\\) \\{[\\s\\S]*?^    \\}`, "gm"), `DesktopSession.${name}`),
  );
  const boundary = "\nstruct Occlusion: OptionSet";
  assert.equal(fixture.split(boundary).length, 2, "the frozen fixture must have one rendering-only boundary");
  const swift = (fixture.split(boundary)[0] + "\n" + checks)
    .replace("// PRODUCTION_SNAPSHOT", one(media, /^struct DesktopSnapshot \{[\s\S]*?^\}/gm, "DesktopSnapshot"))
    .replace("// PRODUCTION_JSON_NUMBER", one(media, /^func jsonNumber\([^\n]*\) -> Double\? \{[\s\S]*?^\}/gm, "jsonNumber"))
    .replace("    // PRODUCTION_SESSION_METHODS", methods.join("\n\n"))
    .replace("    // PRODUCTION_INPUT", one(view, /^    private struct Input: Equatable \{[\s\S]*?^    \}/gm, "DesktopGlassPoster.Input"))
    .replace("    // PRODUCTION_ARRIVAL", one(view, /^    private struct Arrival \{[\s\S]*?^    \}/gm, "DesktopGlassPoster.Arrival"))
    .replace("    // PRODUCTION_RECEIVE", one(view, /^    private func receive\(_ value: Input\) \{[\s\S]*?^    \}/gm, "DesktopGlassPoster.receive"));
  const directory = await mkdtemp(join(tmpdir(), "likeit-lyric-continuity-"));
  try {
    const driver = join(directory, "driver.swift"), binary = join(directory, "acceptance");
    await writeFile(driver, swift);
    await exec("xcrun", ["swiftc", "native/ImmersiveCore.swift", "native/DesktopCommunityLyricsCore.swift", "native/DesktopView.swift", driver, "-o", binary], { cwd: root, timeout: 90000, maxBuffer: 1024 * 1024 });
    const { stdout } = await exec(binary, [], { timeout: 10000, maxBuffer: 1024 * 1024 });
    const results = JSON.parse(stdout);
    assert.equal(results.length, 21, "every frozen continuity scenario must execute");
    assert.equal(new Set(results.map(result => result.name)).size, results.length, "scenario names must be unique");
    for (const result of results) await t.test(result.name, () => assert.equal(result.passed, true));
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
