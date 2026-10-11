import AppKit
import SwiftUI

// Reviewer-only sequential fixture. Diff from render-poster.swift: start at 3.9s before cue 4.0s.
// The original fixture jumps 0.5s to 4.0s, deliberately retained as the seek case.
// Runs the actual View without media, network or capture.
@main struct PosterPreview {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "com.likeit.review.poster." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DesktopModel(themeDefaults: defaults)
        model.selectTheme("glass")
        model.title = "An Open Window · 一扇敞开的窗"
        model.artist = "Original reviewer text / Synthetic Artist"
        model.status = "原创验收输入 · 非实机歌词"
        model.audioStatus = "Synthetic bands · 非音频采集"
        model.progress = 0.42
        let texts = ["Let the light in", "Keep the room awake", "风穿过玻璃", "Every small moment", "A sudden turn", "Find a little space", "把此刻留住", "One more open window"]
        let rows = texts.enumerated().map { DesktopGlassLyricLine(cue: DesktopLyricCue(trackKey: "fixture-a", index: $0.offset, start: Double($0.offset * 4)), text: $0.element) }
        func setLine(_ index: Int, position: Double? = nil) {
            let start = index < 4 ? 0 : 4
            model.glassPage = Array(rows[start..<(start + 4)])
            model.lyric = texts[index]
            model.lyricPosition = position ?? rows[index].cue.start + 0.5
            model.lyricCue = rows[index].cue
            model.translation = ["让光走进来", "让房间保持清醒", "The wind passes through glass", "每一个细小瞬间"][index % 4]
            model.previousLine = index > 0 ? texts[index - 1] : ""
            model.nextLine = index + 1 < texts.count ? texts[index + 1] : ""
        }
        func wait(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(max(0, seconds))) }
        func host(_ width: Double, _ height: Double) -> (NSHostingView<some View>, NSWindow) {
            let view = NSHostingView(rootView: DesktopView(model: model, retryAudio: {}, exit: {}).frame(width: width, height: height))
            view.frame = NSRect(x: 0, y: 0, width: width, height: height)
            let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            return (view, window)
        }
        func bitmap(_ view: NSView) -> NSBitmapImageRep {
            view.layoutSubtreeIfNeeded()
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width), pixelsHigh: Int(view.bounds.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("bitmap") }
            bitmap.size = view.bounds.size
            view.cacheDisplay(in: view.bounds, to: bitmap)
            return bitmap
        }
        func capture(_ view: NSView) throws -> Data {
            guard let png = bitmap(view).representation(using: .png, properties: [:]) else { fatalError("png") }
            return png
        }
        func still(_ name: String, width: Double = 1280, height: Double = 800) throws {
            let (view, window) = host(width, height)
            defer { window.close() }
            wait(0.15)
            try capture(view).write(to: output.appendingPathComponent(name + ".png"))
        }
        setLine(3)
        for scene in DesktopGlassScene.allCases {
            model.selectGlassScene(scene.rawValue)
            try still(scene.rawValue)
        }
        model.selectGlassScene("celadon")
        try still("small-800", width: 800, height: 600)
        try still("wide-1920", width: 1920, height: 1080)
        setLine(1)
        try still("page-half-revealed")
        let long = ["这是检查真实长句的原创文本：清晨的阳光穿过窗边，让每一个普通日子变得明亮 👩🏽‍💻 🌤️", "Every little word deserves enough room to remain readable, even when a very long sentence reaches the edge of this glass.", "保留大小写 Keep Case e\u{301} 👨‍👩‍👧‍👦", "此刻"]
        model.glassPage = long.enumerated().map { DesktopGlassLyricLine(cue: rows[$0.offset].cue, text: $0.element) }
        model.lyricCue = rows[3].cue; model.lyric = long[3]
        try still("long-800", width: 800, height: 600)
        try still("long-1280")
        model.glassPage = []; model.lyricCue = nil
        model.plainLyrics = (1...18).map { "第\($0)行 · 原创未同步歌词\nAn original line without timing." }.joined(separator: "\n")
        try still("plain")
        model.plainLyrics = nil; model.lyric = ""; model.translation = ""
        model.status = "暂无可用歌词 · 信息未知"
        model.audioStatus = "音频采集失败 · 可重试"; model.canRetryAudio = true
        try still("unavailable-800", width: 800, height: 600)
        model.canRetryAudio = false
        model.status = "原创验收输入 · 非实机歌词"; model.audioStatus = "Synthetic bands · 非音频采集"
        setLine(0, position: 3.9)
        model.motionEnabled = true
        let (view, window) = host(1280, 800)
        defer { window.close() }
        wait(0.2)
        try capture(view).write(to: output.appendingPathComponent("entry-before.png"))
        var timing: [[String: Any]] = []
        func sequence(_ name: String, duration: Double, update: (Double) -> Void) throws {
            let start = ProcessInfo.processInfo.systemUptime
            var frame = 0
            var frames: [(String, NSBitmapImageRep)] = []
            repeat {
                let elapsed = ProcessInfo.processInfo.systemUptime - start
                update(elapsed)
                wait(0.001)
                let before = ProcessInfo.processInfo.systemUptime - start
                let rendered = bitmap(view)
                let filename = String(format: "%@-%03d.png", name, frame)
                frames.append((filename, rendered))
                timing.append(["sequence": name, "frame": frame, "sampleMs": before * 1000, "finishMs": (ProcessInfo.processInfo.systemUptime - start) * 1000, "file": filename])
                frame += 1
                wait(Double(frame) / 60 - (ProcessInfo.processInfo.systemUptime - start))
            } while ProcessInfo.processInfo.systemUptime - start < duration
            for (filename, rendered) in frames {
                guard let data = rendered.representation(using: .png, properties: [:]) else { fatalError("png") }
                try data.write(to: output.appendingPathComponent(filename))
            }
        }
        setLine(1, position: 4)
        try sequence("entry", duration: 0.65) { elapsed in
            model.lyricPosition = 4 + floor(elapsed * 10) / 10
        }
        wait(0.2)
        try capture(view).write(to: output.appendingPathComponent("entry-settled.png"))
        setLine(3, position: 15.9)
        wait(0.15)
        setLine(4, position: 16)
        try sequence("page", duration: 0.65) { elapsed in
            model.lyricPosition = 16 + floor(elapsed * 10) / 10
        }
        setLine(5, position: 20)
        wait(0.07)
        setLine(1, position: 4.2)
        model.motionEnabled = false
        wait(0.02)
        try capture(view).write(to: output.appendingPathComponent("interrupted-off.png"))
        wait(0.7)
        try capture(view).write(to: output.appendingPathComponent("off-stable.png"))
        setLine(3)
        for scene in DesktopGlassScene.allCases {
            model.selectGlassScene(scene.rawValue)
            model.motionEnabled = true
            model.low = 0; model.mid = 0; model.high = 0
            wait(0.15); try capture(view).write(to: output.appendingPathComponent(scene.rawValue + "-rest.png"))
            model.low = 0.4; model.mid = 0.3; model.high = 0.45
            try sequence(scene.rawValue + "-pulse", duration: 0.25) { _ in }
            model.low = 0; model.mid = 0; model.high = 0
            wait(0.15); try capture(view).write(to: output.appendingPathComponent(scene.rawValue + "-zero.png"))
        }
        let json = try JSONSerialization.data(withJSONObject: timing, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: output.appendingPathComponent("capture-timing.json"))
    }
}
