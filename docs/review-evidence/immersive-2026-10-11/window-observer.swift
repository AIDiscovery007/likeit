import AppKit
import CoreGraphics

let duration = min(60.0, max(1.0, Double(CommandLine.arguments.dropFirst().first ?? "30") ?? 30))
let began = ProcessInfo.processInfo.systemUptime
var transitions: [[String: Any]] = []
var previous = ""
var frames = Set<String>()
var seen = Set<pid_t>()
var visibleSamples = 0
var firstVisible: Double?
var lastVisible: Double?
while ProcessInfo.processInfo.systemUptime - began < duration {
    let elapsed = ProcessInfo.processInfo.systemUptime - began
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.likeit.desktop")
    let pids = Set(apps.map(\.processIdentifier))
    seen.formUnion(pids)
    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
    let state = "\(front)|\(pids.sorted())"
    if state != previous {
        transitions.append(["seconds": elapsed, "front": front, "desktopPIDs": pids.sorted()])
        previous = state
    }
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let owned = windows.filter { pids.contains(($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? -1) }
    if !owned.isEmpty {
        visibleSamples += 1
        firstVisible = firstVisible ?? elapsed
        lastVisible = elapsed
        for window in owned {
            frames.insert(String(describing: window[kCGWindowBounds as String] ?? "unknown"))
        }
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.025))
}
let value: [String: Any] = ["transitions": transitions, "observedPIDs": seen.sorted(), "frames": frames.sorted(), "visibleSamples": visibleSamples, "firstVisible": firstVisible as Any? ?? NSNull(), "lastVisible": lastVisible as Any? ?? NSNull(), "reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion]
let bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted])
print(String(decoding: bytes, as: UTF8.self))
