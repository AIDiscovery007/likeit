import test from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
const root = fileURLToPath(new URL("../", import.meta.url));
test("cache review: malformed word timing and interrupted writes recover safely", async t => {
  const dir = mkdtempSync(join(tmpdir(), "likeit-cache-review-"));
  try {
    const binary = join(dir, "acceptance");
    const community = readdirSync(join(root, "native")).filter(n => /^DesktopCommunityLyrics.*\.swift$/.test(n)).map(n => "native/" + n);
    execFileSync("xcrun", ["swiftc", "native/ImmersiveCore.swift", "native/DesktopMedia.swift", "native/OpenAPILyricCore.swift", "native/DesktopOpenAPILyrics.swift", "native/DesktopLyrics.swift", ...community, "acceptance/lyrics-cache-review-regressions.swift", "-o", binary], { cwd: root, timeout: 120000, stdio: "pipe" });
    const checks = JSON.parse(execFileSync(binary, [dir], { timeout: 15000, encoding: "utf8" }));
    assert.equal(checks.length, 5);
    for (const check of checks) await t.test(check.name, () => assert.equal(check.passed, true));
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
