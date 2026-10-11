import { test } from "node:test";
import assert from "node:assert/strict";
import { verify } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
test("official provider and real desktop integration stay within frozen boundaries", async (t) => {
  const directory = mkdtempSync(join(tmpdir(), "likeit-openapi-provider-"));
  try {
    const binary = join(directory, "acceptance");
    execFileSync("swiftc", ["native/ImmersiveCore.swift", "native/DesktopMedia.swift", "native/OpenAPILyricCore.swift", "native/DesktopOpenAPILyrics.swift", "native/DesktopLyrics.swift", "acceptance/openapi-lyrics-provider-driver.swift", "-o", binary], { cwd: root, timeout: 120000, stdio: "pipe" });
    const output = JSON.parse(execFileSync(binary, [join(root, "acceptance/fixtures/openapi"), directory], { timeout: 30000, encoding: "utf8", maxBuffer: 4 * 1024 * 1024 }));
    assert.equal(output.checks.length, 41, "all frozen provider scenarios execute");
    for (const check of output.checks) await t.test(check.name, () => assert.equal(check.passed, true));
    await t.test("every emitted request is independently signature-verified", () => {
      assert.ok(output.requests.length >= 25);
      const publicKey = readFileSync(join(root, "acceptance/fixtures/openapi/public.pem"));
      for (const request of output.requests) {
        assert.equal(request.host, "openapi.music.163.com");
        assert.match(request.path, /^\/openapi\/[a-zA-Z0-9_/-]+$/);
        const fields = request.fields;
        assert.equal(fields.appId, "fixture-app");
        assert.equal(fields.accessToken, "fixture-token");
        assert.equal(fields.signType, "RSA_SHA256");
        assert.match(fields.timestamp, /^\d{13}$/);
        assert.equal(JSON.parse(fields.device).deviceId, "fixture-device");
        assert.equal(typeof JSON.parse(fields.bizContent), "object");
        const canonical = Object.keys(fields).filter((key) => key !== "sign" && fields[key] !== "").sort().map((key) => `${key}=${fields[key]}`).join("&");
        assert.equal(verify("RSA-SHA256", Buffer.from(canonical), publicKey, Buffer.from(fields.sign, "base64")), true);
      }
    });
  } finally { rmSync(directory, { recursive: true, force: true }); }
});
