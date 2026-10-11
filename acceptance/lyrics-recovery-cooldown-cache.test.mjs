import test from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
const root = fileURLToPath(new URL("../", import.meta.url));
test("cached exact lyrics remain available before public and official cooldown gates", { timeout: 120000 }, async t => {
  const dir = mkdtempSync(join(tmpdir(), "likeit-cooldown-cache-"));
  try {
    const binary = join(dir, "acceptance");
    const sources = readdirSync(join(root, "native")).filter(n => /^Desktop(CommunityLyrics|LyricRecovery).*\.swift$/.test(n)).map(n => "native/" + n);
    execFileSync("xcrun", ["swiftc", "native/ImmersiveCore.swift", "native/DesktopMedia.swift", "native/OpenAPILyricCore.swift", "native/DesktopOpenAPILyrics.swift", "native/DesktopLyrics.swift", ...sources, "acceptance/lyrics-recovery-cooldown-cache.swift", "-o", binary], { cwd: root, timeout: 90000, stdio: "pipe" });
    for (const mode of ["public", "official"]) {
      const checks = JSON.parse(execFileSync(binary, [join(dir, mode), mode, join(root, "acceptance/fixtures/openapi/private.pem")], { timeout: 16000, encoding: "utf8" }));
      assert.equal(checks.length, 4);
      for (const check of checks) await t.test(check.name, () => assert.equal(check.passed, true));
    }
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
