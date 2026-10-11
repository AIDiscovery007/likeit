import test from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
const root = fileURLToPath(new URL("../", import.meta.url));
test("R2: word highlighting uses original text positions", async t => {
  const directory = mkdtempSync(join(tmpdir(), "likeit-highlight-r2-"));
  try {
    const binary = join(directory, "acceptance");
    execFileSync("xcrun", ["swiftc", "native/ImmersiveCore.swift", "native/DesktopCommunityLyricsCore.swift", "native/DesktopView.swift", "acceptance/community-lyrics-highlight-regression.swift", "-o", binary], { cwd: root, timeout: 90000, stdio: "pipe" });
    const results = JSON.parse(execFileSync(binary, [], { timeout: 5000, encoding: "utf8" }));
    assert.equal(Object.keys(results).length, 16);
    for (const [name, passed] of Object.entries(results)) await t.test(name, () => assert.equal(passed, true));
  } finally { rmSync(directory, { recursive: true, force: true }); }
});
