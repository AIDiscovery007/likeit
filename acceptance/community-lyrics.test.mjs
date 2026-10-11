import test from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
test("C01–C16: production community lyrics satisfy frozen offline behavior", { timeout: 160000 }, async t => {
  const directory = mkdtempSync(join(tmpdir(), "likeit-community-"));
  try {
    const sources = readdirSync(join(root, "native")).filter(n => /^DesktopCommunityLyrics.*\.swift$/.test(n)).map(n => "native/" + n);
    assert.ok(sources.length > 0, "community provider is not implemented");
    const binary = join(directory, "acceptance");
    execFileSync("xcrun", ["swiftc", "native/ImmersiveCore.swift", "native/DesktopMedia.swift", "native/OpenAPILyricCore.swift", "native/DesktopOpenAPILyrics.swift", "native/DesktopLyrics.swift", ...sources, "acceptance/community-lyrics-driver.swift", "-o", binary], { cwd: root, timeout: 120000, stdio: "pipe" });
    const results = JSON.parse(execFileSync(binary, [], { timeout: 35000, encoding: "utf8", maxBuffer: 1024 * 1024 }));
    assert.equal(results.length, 51, "every frozen scenario must execute");
    for (const result of results) await t.test(result.name, () => assert.equal(result.passed, true));
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

test("C15: community is an explicit source and legacy remains default", () => {
  const manifest = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
  const source = manifest.preferences.find(p => p.name === "desktopLyricsSource");
  assert.ok(source, "lyrics source preference missing");
  assert.equal(source.type, "dropdown");
  assert.equal(source.default, "netease");
  assert.deepEqual(source.data.map(p => p.value), ["netease", "community"]);
  assert.ok(readFileSync(join(root, "src/music-desktop.tsx"), "utf8").includes("desktopLyricsSource"), "preference reaches the launcher");
  assert.ok(readFileSync(join(root, "native/DesktopSession.swift"), "utf8").includes("CommunityLyrics"), "real desktop owns community provider");
});
