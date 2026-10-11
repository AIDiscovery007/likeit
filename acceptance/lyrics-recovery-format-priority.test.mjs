import test from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
const root = fileURLToPath(new URL("../", import.meta.url));
test("LRCLIB prefers available synced text, then plain text, then instrumental", { timeout: 120000 }, async t => {
  const dir = mkdtempSync(join(tmpdir(), "likeit-format-priority-"));
  try {
    const binary = join(dir, "acceptance");
    const sources = readdirSync(join(root, "native")).filter(n => /^Desktop(CommunityLyrics|LyricRecovery).*\.swift$/.test(n)).map(n => "native/" + n);
    execFileSync("xcrun", ["swiftc", "native/ImmersiveCore.swift", "native/DesktopMedia.swift", "native/OpenAPILyricCore.swift", "native/DesktopOpenAPILyrics.swift", "native/DesktopLyrics.swift", ...sources, "acceptance/lyrics-recovery-format-priority.swift", "-o", binary], { cwd: root, timeout: 90000, stdio: "pipe" });
    const checks = JSON.parse(execFileSync(binary, [dir], { timeout: 16000, encoding: "utf8" }));
    assert.equal(checks.length, 4);
    for (const check of checks) await t.test(check.name, () => assert.equal(check.passed, true));
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
