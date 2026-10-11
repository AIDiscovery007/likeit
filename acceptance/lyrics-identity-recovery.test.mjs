import test from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
const root = fileURLToPath(new URL("../", import.meta.url));
test("real lyric acquisition: Netease then AMLL then LRCLIB, optional metadata, restart cache", { timeout: 180000 }, async t => {
  const dir = mkdtempSync(join(tmpdir(), "likeit-lyric-recovery-"));
  try {
    const binary = join(dir, "acceptance");
    const additional = readdirSync(join(root, "native")).filter(n => /^Desktop(CommunityLyrics|LyricRecovery).*\.swift$/.test(n)).map(n => "native/" + n);
    execFileSync("xcrun", ["swiftc", "native/ImmersiveCore.swift", "native/DesktopMedia.swift", "native/OpenAPILyricCore.swift", "native/DesktopOpenAPILyrics.swift", "native/DesktopLyrics.swift", ...additional, "acceptance/lyrics-identity-recovery.swift", "-o", binary], { cwd: root, timeout: 90000, stdio: "pipe" });
    for (const [stage, count] of [["checks", 36], ["seed", 2], ["hit", 2]]) {
      const checks = JSON.parse(execFileSync(binary, [stage, dir, join(root, "acceptance/fixtures/openapi/private.pem")], { timeout: 65000, encoding: "utf8" }));
      assert.equal(checks.length, count, "every frozen behavior executed");
      for (const check of checks) await t.test(check.name, () => assert.equal(check.passed, true));
    }
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
test("desktop uses the acquisition flow and keeps obtained lyrics visible without a clock", () => {
  const session = readFileSync(join(root, "native/DesktopSession.swift"), "utf8");
  assert.match(session, /DesktopLyricRecovery\(/);
  assert.match(session, /\.load\([\s\S]*preferredSource:/);
  assert.match(session, /\.readableText/);
});
