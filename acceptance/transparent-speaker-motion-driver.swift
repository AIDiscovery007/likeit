import Foundation
import SwiftUI

// OS input only: production snapshot parsing and playbackPosition remain unchanged.
let neteaseBundle = "com.netease.163music"
var musicPID: pid_t? = 77
func neteasePID() -> pid_t? { musicPID }
// PRODUCTION_JSON_NUMBER
// PRODUCTION_SNAPSHOT

// These sinks replace provider/process teardown and timer scheduling, not lyric decisions.
final class StopProbe {
    var stops = 0, cancellations = 0
    func stop() { stops += 1 }
    func cancel() { cancellations += 1 }
}
final class RenderProbe {
    let model: DesktopModel
    let recovery = StopProbe()
    var readableText: String?
    var communityDocument: CommunityLyricDocument?
    var lyricGeneration = UUID()
    var state = LyricState()
    var snapshot: DesktopSnapshot?
    var running = true, revision = 0
    var heartbeat: Timer?, clock: Timer?
    var stream: StopProbe?, reader: StopProbe?
    var lyricStatus = "已取得真实歌词"
    var sourceChanged: ((DesktopSnapshot?) -> Void)?
    init(_ model: DesktopModel) { self.model = model }
    func scheduleClock() {}
    func refresh() { render() }
    func clearDisplay() { clearDisplayedLyrics() }
    func clearAll() { clear() }
    // PRODUCTION_SESSION_METHODS
}

struct Occlusion: OptionSet {
    let rawValue: Int
    static let visible = Occlusion(rawValue: 1)
}
final class WindowProbe { var occlusionState: Occlusion = .visible }
final class NSWorkspace {
    static let shared = NSWorkspace()
    var accessibilityDisplayShouldReduceMotion = false
}
struct MotionSnapshot {
    var pid: pid_t = 77
    var playing = true
    var sampledAt = ProcessInfo.processInfo.systemUptime
}
final class VisibilityProbe {
    var visible: Bool?
    func setVisible(_ value: Bool) { visible = value }
}
final class AudioProbe {
    var pids: [pid_t?] = []
    func update(pid: pid_t?, reason: String) { pids.append(pid) }
}
final class MotionProbe {
    let model: DesktopModel
    let audio = AudioProbe()
    var window: WindowProbe? = WindowProbe()
    var session: VisibilityProbe? = VisibilityProbe()
    var snapshot: MotionSnapshot? = MotionSnapshot()
    var terminating = false
    var mode = "always"
    init(_ model: DesktopModel) { self.model = model }
    func refresh() { updateMotion() }
    func stopPermission() { allowAudio = false }
    var permitted: Bool { allowAudio }
    // PRODUCTION_ALLOW_AUDIO
    // PRODUCTION_UPDATE_MOTION
}

@main enum TransparentSpeakerMotionAcceptance {
    static func main() {
        let suite = "com.likeit.acceptance.glass-motion." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var results: [[String: Any]] = []
        func check(_ name: String, _ passed: Bool) { results.append(["name": name, "passed": passed]) }
        func snapshot(_ position: Double?, track: String = "track-a", playing: Bool = false) -> DesktopSnapshot {
            var data: [String: Any] = [
                "bundleIdentifier": neteaseBundle, "processIdentifier": 77,
                "contentItemIdentifier": track, "title": "同名歌曲", "artist": "Artist", "album": "Album",
                "durationMicros": 120_000_000, "playing": playing,
                "timestampEpochMicros": Date().timeIntervalSince1970 * 1_000_000,
            ]
            if let position {
                data["elapsedTimeMicros"] = position * 1_000_000
                data["playbackRate"] = playing ? 1.0 : 0.0
            }
            return DesktopSnapshot(data, expectedPID: 77)!
        }
        let model = DesktopModel(themeDefaults: defaults), probe = RenderProbe(DesktopModel(themeDefaults: defaults))
        check("motion defaults off without a session", !model.motionEnabled)
        check("new model has no invented lyric clock or cue", model.lyricCue == nil && model.lyricPosition == nil)
        let identity = DesktopLyricCue(trackKey: "a", index: 0, start: 1)
        check("cue equality distinguishes track index and start independently", identity == DesktopLyricCue(trackKey: "a", index: 0, start: 1) && identity != DesktopLyricCue(trackKey: "b", index: 0, start: 1) && identity != DesktopLyricCue(trackKey: "a", index: 1, start: 1) && identity != DesktopLyricCue(trackKey: "a", index: 0, start: 2))
        let lines = parseLRC("[00:01.00]重复 Repeated 👩🏽‍💻\n[00:03.00]重复 Repeated 👩🏽‍💻\n[00:06.00]下一行")
        func load(_ value: DesktopSnapshot, lines: [LyricLine]) {
            probe.snapshot = value
            probe.state.beginTrack(value.key)
            probe.state.accept(lines, for: value.key)
        }
        load(snapshot(0.5), lines: lines)
        probe.refresh()
        check("before the first LRC line has position but no cue", probe.model.lyricCue == nil && probe.model.lyricPosition == 0.5)
        probe.snapshot = snapshot(1.2)
        probe.refresh()
        let first = DesktopLyricCue(trackKey: probe.snapshot!.key, index: 0, start: 1)
        check("LRC cue contains the verified track key index and timestamp", probe.model.lyricCue == first && probe.model.lyricPosition == 1.2 && probe.model.lyric == lines[0].text)
        probe.snapshot = snapshot(1.3)
        probe.refresh()
        check("100ms within one LRC line advances position without a new cue", probe.model.lyricCue == first && probe.model.lyricPosition == 1.3)
        probe.snapshot = snapshot(3.2)
        probe.refresh()
        check("repeated text at a new LRC timestamp has a new cue", probe.model.lyricCue == DesktopLyricCue(trackKey: first.trackKey, index: 1, start: 3) && probe.model.lyricCue != first && probe.model.lyric == lines[0].text)
        load(snapshot(1.2, track: "track-b"), lines: lines)
        probe.refresh()
        check("same title and lyrics on another track have a different cue", probe.model.lyricCue == DesktopLyricCue(trackKey: probe.snapshot!.key, index: 0, start: 1) && probe.model.lyricCue != first)
        probe.snapshot = snapshot(0.5, track: "track-b")
        probe.refresh()
        check("seeking before the first LRC line clears the previous cue", probe.model.lyricCue == nil && probe.model.lyricPosition == 0.5)
        probe.snapshot = snapshot(6.2, track: "track-b")
        probe.refresh()
        probe.snapshot = snapshot(1.2, track: "track-b")
        probe.refresh()
        check("backward seeks immediately publish the target LRC cue", probe.model.lyricCue == DesktopLyricCue(trackKey: probe.snapshot!.key, index: 0, start: 1) && probe.model.lyricPosition == 1.2)

        let communityLines = [
            CommunityLyricLine(start: 1, end: 3, text: "Hello 世界", translation: "你好世界", words: [CommunityLyricWord(start: 1, end: 2, text: "Hello", utf16Range: NSRange(location: 0, length: 5))]),
            CommunityLyricLine(start: 3, end: 5, text: "Hello 世界", translation: "重复句", words: []),
        ]
        probe.communityDocument = CommunityLyricDocument(source: .amll, lines: communityLines, plainText: nil, instrumental: false)
        probe.snapshot = snapshot(1.2, track: "track-b", playing: true)
        probe.refresh()
        let communityCue = DesktopLyricCue(trackKey: probe.snapshot!.key, index: 0, start: 1)
        let highlighted = probe.model.timedLyric
        check("community rendering publishes its real cue and trusted position", probe.model.lyricCue == communityCue && (1.2..<1.3).contains(probe.model.lyricPosition ?? -1) && probe.model.translation == "你好世界")
        probe.snapshot = snapshot(1.3, track: "track-b", playing: true)
        probe.refresh()
        check("100ms word highlighting changes without replaying the line cue", probe.model.lyricCue == communityCue && probe.model.timedLyric != highlighted && (1.3..<1.4).contains(probe.model.lyricPosition ?? -1))
        probe.snapshot = snapshot(3.2, track: "track-b")
        probe.refresh()
        check("repeated community text is identified by its new index and start", probe.model.lyricCue == DesktopLyricCue(trackKey: communityCue.trackKey, index: 1, start: 3) && probe.model.lyricCue != communityCue)
        load(snapshot(1.2, track: "track-c"), lines: [])
        probe.refresh()
        check("community cue changes track even when the text is identical", probe.model.lyricCue == DesktopLyricCue(trackKey: probe.snapshot!.key, index: 0, start: 1) && probe.model.lyricCue != communityCue)
        probe.snapshot = snapshot(0.5, track: "track-c")
        probe.refresh()
        check("community seek before its first line clears the cue", probe.model.lyricCue == nil && probe.model.lyricPosition == 0.5)
        probe.snapshot = snapshot(1.2, track: "track-c")
        probe.refresh()
        let preservedCue = DesktopLyricCue(trackKey: probe.snapshot!.key, index: 0, start: 1), preservedText = probe.model.timedLyric
        probe.model.motionEnabled = true
        for _ in 0..<10 {
            probe.model.selectTheme("glass"); probe.model.selectGlassScene("night")
            probe.model.selectTheme("classic"); probe.model.selectGlassScene("paper")
        }
        check("theme and scene round trips retain cue position permission and highlighting", probe.model.lyricCue == preservedCue && probe.model.lyricPosition == 1.2 && probe.model.motionEnabled && probe.model.timedLyric == preservedText)
        probe.snapshot = snapshot(nil, track: "track-c")
        probe.readableText = "静态全文\n完整保留"
        probe.refresh()
        check("missing trusted progress clears cue and position but retains static lyrics", probe.model.lyricCue == nil && probe.model.lyricPosition == nil && probe.model.plainLyrics == probe.readableText && probe.model.timedLyric == nil)

        // Seed a stale cue deliberately: each alternate rendering branch must remove it.
        probe.snapshot = snapshot(4, track: "track-c")
        probe.model.lyricCue = preservedCue
        probe.communityDocument = CommunityLyricDocument(source: .lrclib, lines: [], plainText: "纯文本\n无时间戳", instrumental: false)
        probe.refresh()
        check("plain lyrics keep real progress without an invented line cue", probe.model.lyricCue == nil && probe.model.lyricPosition == 4 && probe.model.plainLyrics == "纯文本\n无时间戳")
        probe.model.lyricCue = preservedCue
        probe.communityDocument = CommunityLyricDocument(source: .lrclib, lines: [], plainText: nil, instrumental: true)
        probe.refresh()
        check("instrumental music keeps real progress without a lyric cue", probe.model.lyricCue == nil && probe.model.lyricPosition == 4 && probe.model.lyric == "纯音乐")
        probe.model.lyricCue = preservedCue
        probe.communityDocument = nil
        probe.state.accept([], for: probe.snapshot!.key)
        probe.refresh()
        check("an empty synchronized document has no stale cue", probe.model.lyricCue == nil && probe.model.lyricPosition == 4)
        probe.model.lyricCue = preservedCue; probe.model.lyricPosition = 4
        probe.clearDisplay()
        check("clearing displayed lyrics removes both cue and clock", probe.model.lyricCue == nil && probe.model.lyricPosition == nil)
        probe.model.lyricCue = preservedCue; probe.model.lyricPosition = 4
        probe.clearAll()
        check("clearing the source removes both cue and clock", probe.model.lyricCue == nil && probe.model.lyricPosition == nil && probe.snapshot == nil)
        load(snapshot(1.2), lines: lines)
        probe.refresh()
        musicPID = nil
        probe.refresh()
        check("loss of the verified music process clears cue and clock", probe.model.lyricCue == nil && probe.model.lyricPosition == nil && probe.snapshot == nil)
        musicPID = 77
        load(snapshot(1.2), lines: lines)
        probe.refresh()
        probe.stop()
        check("stopping the real session clears cue and clock", probe.model.lyricCue == nil && probe.model.lyricPosition == nil && !probe.running && probe.recovery.stops == 1)

        func motion(_ name: String, configure: (MotionProbe) -> Void, enabled: Bool) {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion = false
            let motion = MotionProbe(DesktopModel(themeDefaults: defaults))
            motion.model.motionEnabled = !enabled
            configure(motion)
            motion.refresh()
            check(name, motion.model.motionEnabled == enabled && motion.permitted == enabled && motion.audio.pids == [enabled ? 77 : nil])
        }
        motion("visible playing always publishes motion permission", configure: { _ in }, enabled: true)
        motion("audio permission failure does not disable trusted lyric motion", configure: {
            $0.model.audioStatus = "音频权限不可用 · 保持静态"
            $0.model.canRetryAudio = true
            $0.model.low = 0; $0.model.mid = 0; $0.model.high = 0
        }, enabled: true)
        motion("system without Reduce Motion publishes motion permission", configure: { $0.mode = "system" }, enabled: true)
        motion("off revokes published motion permission", configure: { $0.mode = "off" }, enabled: false)
        motion("system with Reduce Motion revokes published permission", configure: { $0.mode = "system"; NSWorkspace.shared.accessibilityDisplayShouldReduceMotion = true }, enabled: false)
        motion("paused music revokes published motion permission", configure: { $0.snapshot?.playing = false }, enabled: false)
        motion("occlusion revokes published motion permission", configure: { $0.window?.occlusionState = [] }, enabled: false)
        motion("stale evidence revokes published motion permission", configure: { $0.snapshot?.sampledAt -= 6 }, enabled: false)
        motion("missing source revokes published motion permission", configure: { $0.snapshot = nil }, enabled: false)
        let motion = MotionProbe(DesktopModel(themeDefaults: defaults))
        motion.refresh()
        motion.stopPermission()
        check("clearing allowAudio also revokes the presentation permission", !motion.model.motionEnabled && !motion.permitted)
        let reopened = DesktopModel(themeDefaults: defaults)
        check("reopening restores theme but never persists a cue clock or motion permission", reopened.theme == .classic && reopened.glassScene == .paper && reopened.lyricCue == nil && reopened.lyricPosition == nil && !reopened.motionEnabled)
        print(String(decoding: try! JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]), as: UTF8.self))
    }
}
