import AppKit
import SwiftUI
@main struct Preview {
 @MainActor static func main() throws {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let model = DesktopModel()
  model.title = "Synthetic Song"; model.artist = "Test Artist"; model.status = "AMLL · 社区网易 ID 关联 · 逐词歌词"; model.audioStatus = "桌面动效已关闭 · 不采集音频"; model.progress = 0.42
  model.previousLine = "Let the morning light come in"
  model.nextLine = "We keep walking into the day"
  let line = parseCommunityTTML("<tt xmlns=\"http://www.w3.org/ns/ttml\" xmlns:ttm=\"http://www.w3.org/ns/ttml#metadata\"><body><div><p begin=\"2s\" end=\"4s\"><span begin=\"2s\" end=\"3s\">Bright</span> <span begin=\"3s\" end=\"4s\">day</span><span ttm:role=\"x-translation\" xml:lang=\"zh-CN\">阳光正好，继续向前</span></p></div></body></tt>").first!
  model.lyric = line.text; model.timedLyric = communityHighlightedText(line, at: 3.35); model.translation = line.translation!
  func save(_ name: String, width: Double = 1440, height: Double = 900) throws {
   let host = NSHostingView(rootView: DesktopView(model: model, retryAudio: {}, exit: {}).frame(width: width, height: height).environment(\.colorScheme, .dark))
   let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
   window.contentView = host
   window.orderBack(nil)
   RunLoop.current.run(until: Date().addingTimeInterval(0.2))
   host.layoutSubtreeIfNeeded()
   guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("bitmap failed") }
   host.cacheDisplay(in: host.bounds, to: bitmap)
   guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("png failed") }
   window.orderOut(nil)
   try png.write(to: URL(fileURLWithPath: "/tmp/likeit-community-preview/" + name + "-native.png"))
  }
  try save("timed")
  model.plainLyrics = Array(repeating: "原创合成文本：每一天都继续向前。\nA synthetic line for static reading.", count: 10).joined(separator: "\n")
  model.status = "LRCLIB · 完整歌曲信息匹配 · 未同步歌词"
  try save("plain")
  model.plainLyrics = nil; model.timedLyric = nil; model.lyric = "这是用于检查长句排版的原创合成歌词，让所有文字都能在窗口中清晰显示"; model.translation = "A synthetic long line checks that the main lyric remains readable within the available window."
  try save("long", width: 1000, height: 700)
 }
}
