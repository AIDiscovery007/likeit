import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
test("JSON encoding cannot bypass numeric precision checks", async (t) => {
  const directory = mkdtempSync(join(tmpdir(), "likeit-json-encoding-"));
  try {
    const driver = join(directory, "driver.swift"), binary = join(directory, "driver");
    writeFileSync(driver, String.raw`import Foundation
@main struct EncodingBoundary {
 static func main() throws {
  var checks: [[String: Any]] = []
  let raw = #"{"code":200.0000000000000000000000000000000000001,"data":{"lrc":"[00:01]原创"}}"#
  for (name, encoding) in [("UTF-16", String.Encoding.utf16), ("UTF-16LE", .utf16LittleEndian), ("UTF-32", .utf32)] {
   if case .malformed = decodeOpenAPIWordLyrics(raw.data(using: encoding)!) { checks.append(["name":name,"passed":true]) }
   else { checks.append(["name":name,"passed":false]) }
  }
  let valid = Data(#"{"code":200,"data":{"lrc":"[00:01]原创"},"ignored":"\u0000"}"#.utf8)
  if case .lines(let lines) = decodeOpenAPIWordLyrics(valid) { checks.append(["name":"escaped NUL in valid UTF-8 JSON remains accepted","passed":lines.first?.text == "原创"]) }
  else { checks.append(["name":"escaped NUL in valid UTF-8 JSON remains accepted","passed":false]) }
  print(String(decoding:try JSONSerialization.data(withJSONObject:checks),as:UTF8.self))
 }
}
`);
    execFileSync("swiftc", ["native/ImmersiveCore.swift", "native/OpenAPILyricCore.swift", driver, "-o", binary], { cwd: root, timeout: 120000, stdio: "pipe" });
    const checks = JSON.parse(execFileSync(binary, { encoding: "utf8", timeout: 10000 }));
    assert.equal(checks.length, 4);
    for (const check of checks) await t.test(check.name, () => assert.equal(check.passed, true));
  } finally { rmSync(directory, { recursive: true, force: true }); }
});
