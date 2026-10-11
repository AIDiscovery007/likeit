import assert from "node:assert/strict";
import test from "node:test";
import { readFile, writeFile, mkdtemp, rm } from "node:fs/promises";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
const exec = promisify(execFile);
const root = fileURLToPath(new URL("../", import.meta.url));

// Execute the production URL handler unchanged; isolate app/session effects with probes.
// This proves routing, not real capture/window lifecycle (covered by separate integration QA).
test("T05 regression: a theme-only URL preserves the active source and motion mode", { timeout: 120000 }, async t => {
  const source = await readFile(join(root, "native/DesktopMain.swift"), "utf8");
  const handler = source.match(/    func application\(_ application: NSApplication, open urls: \[URL\]\) \{[\s\S]*?\n    \}\n/);
  assert.ok(handler, "production URL handler must be inspected if its signature changes");
  const directory = await mkdtemp(join(tmpdir(), "likeit-theme-route-"));
  try {
    const swift = join(directory, "driver.swift");
    await writeFile(swift, `import AppKit
import SwiftUI
final class SourceProbe {
    var updates: [String] = []
    func setLyricsSource(_ source: String) { updates.append(source) }
}
final class RouteProbe {
    let model: DesktopModel
    var lyricsSource = "community"
    var mode = "off"
    var session: SourceProbe? = SourceProbe()
    var previousApp: NSRunningApplication?
    var window: NSWindow?
    var motionUpdates = 0
    init(_ defaults: UserDefaults) { model = DesktopModel(themeDefaults: defaults) }
    func updateMotion() { motionUpdates += 1 }
    func activate() {}
${handler[0]}
}
@main struct Verify {
    static func main() {
        let suite = "com.likeit.acceptance.route." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let route = RouteProbe(defaults)
        let app = NSApplication.shared
        func open(_ value: String) { route.application(app, open: [URL(string: value)!]) }
        var results: [String: Bool] = [:]
        open("likeit-desktop://open?theme=glass")
        results["theme-only selects glass"] = route.model.theme.rawValue == "glass"
        results["theme-only preserves source without reloading"] = route.lyricsSource == "community" && route.session!.updates.isEmpty
        results["theme-only preserves off without enabling capture"] = route.mode == "off"
        open("likeit-desktop://other?theme=classic&mode=always")
        results["invalid host is ignored"] = route.model.theme.rawValue == "glass" && route.mode == "off" && route.motionUpdates == 1
        open("likeit-desktop://open?theme=classic&mode=always&lyricsSource=netease")
        results["explicit fields apply once"] = route.model.theme.rawValue == "classic" && route.mode == "always" && route.lyricsSource == "netease" && route.session!.updates == ["netease"]
        open("likeit-desktop://open?theme=glass&mode=always&lyricsSource=netease")
        results["same source never reloads"] = route.session!.updates == ["netease"]
        open("likeit-desktop://open")
        results["omitted fields retain all selections"] = route.model.theme.rawValue == "glass" && route.mode == "always" && route.lyricsSource == "netease" && route.session!.updates == ["netease"]
        print(String(data: try! JSONSerialization.data(withJSONObject: results), encoding: .utf8)!)
    }
}
`);
    const binary = join(directory, "acceptance");
    await exec("xcrun", ["swiftc", "native/ImmersiveCore.swift", "native/DesktopCommunityLyricsCore.swift", "native/DesktopView.swift", swift, "-o", binary], { cwd: root, timeout: 90000, maxBuffer: 1024 * 1024 });
    const { stdout } = await exec(binary, [], { timeout: 10000 });
    const results = JSON.parse(stdout);
    assert.equal(Object.keys(results).length, 7);
    for (const [name, passed] of Object.entries(results)) await t.test(name, () => assert.equal(passed, true));
  } finally { await rm(directory, { recursive: true, force: true }); }
});
