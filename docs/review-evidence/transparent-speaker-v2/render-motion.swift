import AppKit
import SwiftUI

// Reviewer-only synthetic input. This exercises the production View, not audio capture.
@main struct MotionPreview {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "com.likeit.review.motion." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DesktopModel(themeDefaults: defaults)
        model.selectTheme("glass")
        model.title = "Original motion fixture · 原创动效验收"
        model.artist = "Synthetic input / 无采集"
        model.lyric = "Let the morning in"
        model.previousLine = "A quiet window opens"
        model.nextLine = "让此刻慢慢明亮"
        model.translation = "让清晨的光走进来"
        model.status = "Reviewer fixture · 并非实机歌词"
        model.audioStatus = "Synthetic bands · 并非实机音频"
        model.progress = 0.2
        model.lyricCue = DesktopLyricCue(trackKey: "fixture-a", index: 0, start: 10)
        model.lyricPosition = 12
        let host = NSHostingView(rootView: DesktopView(model: model, retryAudio: {}, exit: {}).frame(width: 1280, height: 800))
        host.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        func wait(_ interval: Double) { RunLoop.current.run(until: Date().addingTimeInterval(interval)) }
        func save(_ name: String) throws {
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("bitmap") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("png") }
            try png.write(to: output.appendingPathComponent(name + ".png"))
        }
        wait(0.6)
        for scene in DesktopGlassScene.allCases {
            model.selectGlassScene(scene.rawValue)
            model.motionEnabled = true
            model.low = 0; model.mid = 0; model.high = 0
            wait(0.6); try save(scene.rawValue + "-rest")
            model.low = 0.8; model.mid = 0.6; model.high = 0.9
            model.lyricPosition = 12.1
            wait(0.6); try save(scene.rawValue + "-energy")
            model.low = 0; model.mid = 0; model.high = 0
            wait(0.6); try save(scene.rawValue + "-zero")
        }
        model.selectGlassScene("celadon")
        model.lyric = "Another light arrives"
        model.translation = "另一束光抵达此刻"
        model.lyricPosition = 20
        model.lyricCue = DesktopLyricCue(trackKey: "fixture-a", index: 1, start: 20)
        wait(0.02); try save("line-020ms")
        model.lyricPosition = 20.15
        wait(0.13); try save("line-150ms")
        model.lyricPosition = 20.6
        wait(0.45); try save("line-600ms")
        model.lyric = "A sudden turn, now here"
        model.lyricPosition = 30
        model.lyricCue = DesktopLyricCue(trackKey: "fixture-a", index: 2, start: 30)
        wait(0.05)
        model.lyric = "This is the newest line"
        model.lyricPosition = 40
        model.lyricCue = DesktopLyricCue(trackKey: "fixture-b", index: 0, start: 40)
        wait(0.05)
        model.motionEnabled = false
        wait(0.02); try save("interrupted-motion-off")
        model.lyricPosition = 40.8
        wait(0.8); try save("motion-off-stable")
    }
}
