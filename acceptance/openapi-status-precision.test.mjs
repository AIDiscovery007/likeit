import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
const root = fileURLToPath(new URL("../", import.meta.url));
test("fractional success codes are rejected before selecting lyrics", async (t) => {
  const directory = mkdtempSync(join(tmpdir(), "likeit-openapi-status-"));
  try {
    const binary = join(directory, "driver");
    execFileSync("swiftc", ["native/ImmersiveCore.swift", "native/DesktopMedia.swift", "native/OpenAPILyricCore.swift", "native/DesktopOpenAPILyrics.swift", "acceptance/openapi-status-precision-driver.swift", "-o", binary], { cwd: root, timeout: 120000, stdio: "pipe" });
    const checks = JSON.parse(execFileSync(binary, [join(root, "acceptance/fixtures/openapi/private.pem")], { encoding: "utf8", timeout: 20000 }));
    assert.equal(checks.length, 5);
    for (const check of checks) await t.test(check.name, () => assert.equal(check.passed, true));
  } finally { rmSync(directory, { recursive: true, force: true }); }
});
