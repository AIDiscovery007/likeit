import Foundation

// Coordinator fixture: no AppKit, no windows, no music or actual audio capture.
struct Occlusion: OptionSet {
    let rawValue: Int
    static let visible = Occlusion(rawValue: 1)
}
final class WindowFixture {
    var occlusionState: Occlusion = .visible
    var isVisible = true
    var isMiniaturized = false
}
final class ApplicationFixture { var isActive = true; var isHidden = false }
let NSApp = ApplicationFixture()
final class NSWorkspace {
    static let shared = NSWorkspace()
    var accessibilityDisplayShouldReduceMotion = false
}
struct SnapshotFixture {
    var pid: Int32 = 77
    var playing = true
    var sampledAt = ProcessInfo.processInfo.systemUptime
}
final class SessionFixture {
    var visible: Bool?
    func setVisible(_ value: Bool) { visible = value }
}
final class AudioFixture {
    var history: [Int32?] = []
    func update(pid: Int32?, reason: String) { history.append(pid) }
}
final class ModelFixture {
    var canRetryAudio = false
    var low = 0.7, mid = 0.4, high = 0.2
    var audioStatus = "网易云实时音频律动"
}
final class DelegateFixture {
    var window: WindowFixture? = WindowFixture()
    var snapshot: SnapshotFixture? = SnapshotFixture()
    var session: SessionFixture? = SessionFixture()
    let audio = AudioFixture(), model = ModelFixture()
    var terminating = false, allowAudio = false
    var mode = "always"
    func refresh() { updateMotion() }
    // PRODUCTION_UPDATE_MOTION
}

@main enum VisibilityProbe {
    static func main() {
        var results: [[String: Any]] = []
        func run(_ name: String, _ body: (DelegateFixture) -> Bool) {
            NSApp.isActive = true; NSApp.isHidden = false
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion = false
            results.append(["case": name, "passed": body(DelegateFixture())])
        }
        run("visible foreground captures") { d in
            d.refresh(); return d.allowAudio && d.audio.history == [77] && d.session?.visible == true
        }
        run("visible inactive window keeps capture and lyric refresh") { d in
            NSApp.isActive = false; d.refresh()
            return d.allowAudio && d.audio.history == [77] && d.session?.visible == true
        }
        run("focus loss neither stops capture nor erases live features") { d in
            d.refresh(); NSApp.isActive = false; d.refresh()
            return d.audio.history == [77, 77] && d.model.low == 0.7 && !d.model.audioStatus.contains("不可见")
        }
        run("fully occluded foreground stops") { d in
            d.window?.occlusionState = []; d.refresh()
            return !d.allowAudio && d.audio.history == [nil] && d.session?.visible == false && d.model.low == 0
        }
        run("hidden inactive window stops") { d in
            NSApp.isActive = false; NSApp.isHidden = true
            d.window?.isVisible = false; d.window?.occlusionState = []; d.refresh()
            return !d.allowAudio && d.audio.history == [nil] && d.session?.visible == false
        }
        run("miniaturized window stops") { d in
            d.window?.isMiniaturized = true; d.window?.occlusionState = []; d.refresh()
            return !d.allowAudio && d.audio.history == [nil] && d.model.low == 0
        }
        run("becoming visible restores capture without focus") { d in
            NSApp.isActive = false; d.window?.occlusionState = []; d.refresh()
            d.window?.occlusionState = .visible; d.refresh()
            return d.audio.history == [nil, 77] && d.session?.visible == true
        }
        run("missing window never captures") { d in
            d.window = nil; d.refresh(); return !d.allowAudio && d.audio.history == [nil]
        }
        run("motion off remains off while visible inactive") { d in
            NSApp.isActive = false; d.mode = "off"; d.refresh()
            return !d.allowAudio && d.audio.history == [nil] && d.session?.visible == true
        }
        run("system reduce motion still prevents capture") { d in
            d.mode = "system"; NSWorkspace.shared.accessibilityDisplayShouldReduceMotion = true; d.refresh()
            return !d.allowAudio && d.audio.history == [nil]
        }
        run("paused source still prevents capture") { d in
            d.snapshot?.playing = false; d.refresh(); return !d.allowAudio && d.audio.history == [nil]
        }
        run("stale source still prevents capture") { d in
            d.snapshot?.sampledAt -= 6; d.refresh(); return !d.allowAudio && d.audio.history == [nil]
        }
        run("missing source still prevents capture") { d in
            d.snapshot = nil; d.refresh(); return !d.allowAudio && d.audio.history == [nil]
        }
        run("terminating ignores late visibility changes") { d in
            d.terminating = true; NSApp.isActive = false; d.refresh(); return d.audio.history.isEmpty
        }
        print(String(decoding: try! JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]), as: UTF8.self))
        exit(results.allSatisfy { $0["passed"] as? Bool == true } ? 0 : 1)
    }
}
