import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
test("official lyric signing and payload contract", async (t) => {
  const directory = mkdtempSync(join(tmpdir(), "likeit-openapi-core-"));
  try {
    const binary = join(directory, "acceptance");
    execFileSync("swiftc", ["native/ImmersiveCore.swift", "native/OpenAPILyricCore.swift", "acceptance/openapi-lyrics-core-driver.swift", "-o", binary], { cwd: root, timeout: 120000, stdio: "pipe" });
    const cases = JSON.parse(execFileSync(binary, [join(root, "acceptance/fixtures/openapi")], { timeout: 10000, encoding: "utf8" }));
    assert.equal(cases.length, 17, "all frozen behavioral checks must execute");
    for (const check of cases) await t.test(check.name, () => assert.equal(check.passed, true));
  } finally { rmSync(directory, { recursive: true, force: true }); }
});
