import AppKit
import SwiftUI

@main struct Preview {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let suite = "com.likeit.preview." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DesktopModel(themeDefaults: defaults)
        model.title = "An Open Window · 一扇敞开的窗"
        model.artist = "原创验收文本 / Synthetic Artist"
        model.previousLine = "夜色渐远，风穿过窗边"
        model.nextLine = "We keep the morning in our hands"
        model.status = "AMLL · 逐字歌词 · 本地缓存"
        model.audioStatus = "桌面动效已关闭 · 不采集音频"
        model.progress = 0.42
        let line = parseCommunityTTML("<tt xmlns=\"http://www.w3.org/ns/ttml\"><body><div><p begin=\"0s\" end=\"4s\"><span begin=\"0s\" end=\"2s\">Let the light</span> <span begin=\"2s\" end=\"4s\">come through</span></p></div></body></tt>").first!
        model.lyric = line.text
        model.timedLyric = communityHighlightedText(line, at: 2.5)
        model.translation = "让光穿过窗边，照亮此刻"
        func save(_ name: String, width: Double = 1280, height: Double = 800) throws {
            let view = DesktopView(model: model, retryAudio: {}, exit: {}).frame(width: width, height: height)
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("bitmap") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("png") }
            try png.write(to: directory.appendingPathComponent(name + ".png"))
            window.close()
        }
        try save("classic")
        model.selectTheme("glass")
        for scene in ["celadon", "dusk", "night", "paper"] {
            model.selectGlassScene(scene)
            try save(scene)
        }
        model.selectGlassScene("celadon")
        model.timedLyric = nil
        model.lyric = "这是检查长句的原创文本：清晨的阳光穿过窗边，让每一个普通日子变得明亮 👩🏽‍💻 🌤️"
        model.translation = "This original long sentence checks that every word remains readable at a smaller window size."
        try save("long-1000", width: 1000, height: 700)
        try save("long-1920", width: 1920, height: 1080)
        model.plainLyrics = (1...18).map { "第\($0)行 · 原创未同步歌词\nAn original line without timing." }.joined(separator: "\n")
        model.status = "LRCLIB · 未同步歌词 · 本地缓存"
        try save("plain")
        model.plainLyrics = nil; model.lyric = ""; model.translation = ""
        model.previousLine = ""; model.nextLine = ""
        model.status = "暂无可用歌词 · 信息未知"
        model.audioStatus = "音频采集失败 · 可重试"
        model.canRetryAudio = true
        try save("unavailable")
        try save("small-800", width: 800, height: 600)
    }
}
