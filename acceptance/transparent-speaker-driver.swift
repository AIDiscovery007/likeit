import Foundation
import SwiftUI

@main struct ThemeAcceptance {
    static func main() {
        let suite = CommandLine.arguments[1]
        let defaults = UserDefaults(suiteName: suite)!
        let action = CommandLine.arguments[2]
        if action == "write" {
            let model = DesktopModel(themeDefaults: defaults)
            model.selectTheme("glass")
            model.selectGlassScene("paper")
            defaults.synchronize()
            return
        }
        if action == "read" {
            let model = DesktopModel(themeDefaults: defaults)
            print("\(model.theme.rawValue)/\(model.glassScene.rawValue)")
            return
        }
        if action == "cleanup" { defaults.removePersistentDomain(forName: suite); return }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        var results: [String: Bool] = [:]
        let model = DesktopModel(themeDefaults: defaults)
        results["T01 default classic/celadon"] = model.theme.rawValue == "classic" && model.glassScene.rawValue == "celadon"
        model.selectTheme("glass")
        results["T02 select glass"] = model.theme.rawValue == "glass" && defaults.string(forKey: "desktopTheme") == "glass"
        results["T02 reopen glass"] = DesktopModel(themeDefaults: defaults).theme.rawValue == "glass"
        model.selectTheme(nil)
        results["T03 omitted selection retains glass"] = model.theme.rawValue == "glass"
        model.selectTheme("classic")
        results["T03 explicit classic remembered"] = DesktopModel(themeDefaults: defaults).theme.rawValue == "classic"
        for raw in ["", "GLASS", "unknown", " glass "] {
            model.selectTheme("glass")
            model.selectTheme(raw)
            results["T03 invalid theme \(raw.debugDescription)"] = model.theme.rawValue == "classic"
        }
        defaults.set("retired-theme", forKey: "desktopTheme")
        defaults.set(42, forKey: "desktopGlassScene")
        let recovered = DesktopModel(themeDefaults: defaults)
        results["T03 corrupt preferences recover"] = recovered.theme.rawValue == "classic" && recovered.glassScene.rawValue == "celadon"
        for scene in ["celadon", "dusk", "night", "paper"] {
            model.selectTheme("glass")
            model.selectGlassScene(scene)
            model.selectTheme("classic")
            model.selectTheme("glass")
            model.selectGlassScene(nil)
            let reopened = DesktopModel(themeDefaults: defaults)
            results["T04 scene \(scene) survives round trip"] = model.glassScene.rawValue == scene && reopened.glassScene.rawValue == scene && defaults.string(forKey: "desktopGlassScene") == scene
        }
        model.selectGlassScene("invalid")
        results["T04 invalid scene fallback"] = model.glassScene.rawValue == "celadon"
        model.title = "真实 Title 👩🏽‍💻"
        model.artist = "艺人 Artist"
        model.lyric = "不要改变 Case 或 重复 重复"
        model.previousLine = "上一行"; model.nextLine = "下一行"
        var timed = AttributedString("timed 👨‍👩‍👧‍👦")
        timed.foregroundColor = .orange
        model.timedLyric = timed; model.translation = "翻译"
        model.plainLyrics = "未同步\n第二行"; model.status = "歌词匹配状态"
        model.audioStatus = "重试状态"; model.canRetryAudio = true
        model.progress = 0.42; model.low = 0.2; model.mid = 0.4; model.high = 0.6
        for _ in 0..<10 {
            model.selectTheme("classic"); model.selectTheme("glass"); model.selectTheme("glass")
            model.selectGlassScene("night"); model.selectGlassScene("paper")
        }
        results["T05 metadata unchanged"] = model.title == "真实 Title 👩🏽‍💻" && model.artist == "艺人 Artist"
        results["T05 lyric text unchanged"] = model.lyric == "不要改变 Case 或 重复 重复" && model.previousLine == "上一行" && model.nextLine == "下一行"
        results["T05 timed and plain lyrics unchanged"] = model.timedLyric == timed && model.translation == "翻译" && model.plainLyrics == "未同步\n第二行"
        results["T05 status and retry unchanged"] = model.status == "歌词匹配状态" && model.audioStatus == "重试状态" && model.canRetryAudio
        results["T05 progress and audio unchanged"] = model.progress == 0.42 && model.low == 0.2 && model.mid == 0.4 && model.high == 0.6
        print(String(data: try! JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
