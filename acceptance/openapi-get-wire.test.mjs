import { test } from "node:test";
import assert from "node:assert/strict";
import { verify } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
const root = fileURLToPath(new URL("../", import.meta.url));
test("GET query survives server form decoding before signature verification", () => {
  const directory = mkdtempSync(join(tmpdir(), "likeit-openapi-wire-"));
  try {
    const binary = join(directory, "driver");
    execFileSync("swiftc", ["native/ImmersiveCore.swift", "native/DesktopMedia.swift", "native/OpenAPILyricCore.swift", "native/DesktopOpenAPILyrics.swift", "acceptance/openapi-get-wire-driver.swift", "-o", binary], { cwd: root, timeout: 120000, stdio: "pipe" });
    const address = execFileSync(binary, [join(root, "acceptance/fixtures/openapi/private.pem")], { encoding: "utf8", timeout: 10000 }).trim();
    const url = new URL(address);
    assert.equal(url.origin, "https://openapi.music.163.com");
    const fields = Object.fromEntries(url.searchParams);
    assert.equal(fields.accessToken, "fixture+token");
    assert.equal(JSON.parse(fields.device).deviceId, "fixture+device/A & B");
    assert.equal(JSON.parse(fields.bizContent).keyword, "原创 & + / 音乐");
    const canonical = Object.keys(fields).filter((key) => key !== "sign" && fields[key] !== "").sort().map((key) => `${key}=${fields[key]}`).join("&");
    assert.equal(verify("RSA-SHA256", Buffer.from(canonical), readFileSync(join(root, "acceptance/fixtures/openapi/public.pem")), Buffer.from(fields.sign, "base64")), true);
  } finally { rmSync(directory, { recursive: true, force: true }); }
});
