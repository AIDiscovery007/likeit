import test from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
test("K01–K12: lyrics persist across real process restarts with identity and lifecycle isolation", { timeout: 180000 }, async t => {
  const dir = mkdtempSync(join(tmpdir(), "likeit-lyrics-cache-"));
  try {
    const binary = join(dir, "acceptance");
    const community = readdirSync(join(root, "native")).filter(n => /^DesktopCommunityLyrics.*\.swift$/.test(n)).map(n => "native/" + n);
    execFileSync("xcrun", ["swiftc", "native/ImmersiveCore.swift", "native/DesktopMedia.swift", "native/OpenAPILyricCore.swift", "native/DesktopOpenAPILyrics.swift", "native/DesktopLyrics.swift", ...community, "acceptance/lyrics-cache-driver.swift", "-o", binary], { cwd: root, timeout: 120000, stdio: "pipe" });
    for (const [stage, count] of [["seed", 5], ["hit", 6], ["checks", 29]]) {
      const checks = JSON.parse(execFileSync(binary, [stage, dir, join(root, "acceptance/fixtures/openapi/private.pem")], { timeout: 55000, encoding: "utf8", maxBuffer: 1024 * 1024 }));
      assert.equal(checks.length, count, `all ${stage} checks executed`);
      for (const check of checks) await t.test(check.name, () => assert.equal(check.passed, true));
    }
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("K12: real desktop enables both persistent providers", () => {
  const session = readFileSync(join(root, "native/DesktopSession.swift"), "utf8");
  assert.match(session, /CommunityLyrics\([^)]*cacheDirectory\s*:/s);
  assert.match(session, /DesktopLyrics\([^)]*cacheDirectory\s*:/s);
});
