import { test } from "node:test";
import assert from "node:assert/strict";
import { createPrivateKey } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
test("invalid PKCS8 attributes must not be ignored", () => {
  const directory = mkdtempSync(join(tmpdir(), "likeit-invalid-key-"));
  try {
    const pem = readFileSync(join(root, "acceptance/fixtures/openapi/private.pem"), "utf8");
    const der = Buffer.from(pem.replace(/-----[^-]+-----|\s/g, ""), "base64");
    const headerLength = der[1] & 128 ? 2 + (der[1] & 127) : 2;
    const content = Buffer.concat([der.subarray(headerLength), Buffer.from([0xa0, 1, 0xff])]);
    const length = Buffer.from(content.length.toString(16).padStart(4, "0"), "hex");
    const broken = Buffer.concat([Buffer.from([0x30, 0x82]), length, content]);
    const invalid = `-----BEGIN PRIVATE KEY-----\n${broken.toString("base64").match(/.{1,64}/g).join("\n")}\n-----END PRIVATE KEY-----\n`;
    assert.throws(() => createPrivateKey(invalid), "independent Node parser rejects the malformed envelope");
    const keyPath = join(directory, "invalid.pem");
    const driver = join(directory, "driver.swift");
    const binary = join(directory, "driver");
    writeFileSync(keyPath, invalid);
    writeFileSync(driver, `import Foundation
@main struct KeyEnvelopeAcceptance {
  static func main() throws {
    let pem = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
    do { _ = try openAPISignature(parameters: ["appId": "fixture"], privateKeyPEM: pem); print("accepted") }
    catch { print("rejected") }
  }
}
`);
    execFileSync("swiftc", ["native/ImmersiveCore.swift", "native/OpenAPILyricCore.swift", driver, "-o", binary], { cwd: root, timeout: 120000, stdio: "pipe" });
    assert.equal(execFileSync(binary, [keyPath], { encoding: "utf8", timeout: 10000 }).trim(), "rejected");
  } finally { rmSync(directory, { recursive: true, force: true }); }
});
