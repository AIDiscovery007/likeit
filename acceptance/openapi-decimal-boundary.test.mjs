import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
const root = fileURLToPath(new URL("../", import.meta.url));
test("Decimal precision is bounded before parsing without inspecting lyric strings", async (t) => {
  const directory = mkdtempSync(join(tmpdir(), "likeit-decimal-boundary-"));
  try {
    const driver = join(directory, "driver.swift"), binary = join(directory, "driver");
    writeFileSync(driver, `import Foundation
@main struct Boundary {
 static func main() throws {
  var checks: [[String:Any]] = []
  for code in ["200.0000000000000000000000000000000000001", "200.00000000000000000000000000000000001"] {
   let raw = "{\\\"code\\\":" + code + ",\\\"data\\\":{\\\"lrc\\\":\\\"[00:01]原创\\\"}}"
   if case .malformed = decodeOpenAPIWordLyrics(Data(raw.utf8)) { checks.append(["name":code,"passed":true]) }
   else { checks.append(["name":code,"passed":false]) }
  }
  let text = "[00:01]数字 \\" 200.0000000000000000000000000000000000001 \\""
  let raw = try JSONSerialization.data(withJSONObject:["code":200,"data":["lrc":text]])
  if case .lines(let lines) = decodeOpenAPIWordLyrics(raw) { checks.append(["name":"long numeric lyric string preserved","passed":lines.first?.text == String(text.dropFirst(7))]) }
  else { checks.append(["name":"long numeric lyric string preserved","passed":false]) }
  print(String(decoding:try JSONSerialization.data(withJSONObject:checks),as:UTF8.self))
 }
}
`);
    execFileSync("swiftc", ["native/ImmersiveCore.swift", "native/OpenAPILyricCore.swift", driver, "-o", binary], { cwd: root, timeout: 120000, stdio: "pipe" });
    const checks = JSON.parse(execFileSync(binary, { encoding: "utf8", timeout: 10000 }));
    assert.equal(checks.length, 3);
    for (const check of checks) await t.test(check.name, () => assert.equal(check.passed, true));
  } finally { rmSync(directory, { recursive: true, force: true }); }
});
