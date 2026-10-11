import SwiftUI

enum DesktopTheme: String, CaseIterable {
    case classic, glass
    var title: String { self == .classic ? "经典音响" : "透明音响" }
}

enum DesktopGlassScene: String, CaseIterable {
    case celadon, dusk, night, paper
    var title: String {
        switch self {
        case .celadon: return "青瓷"
        case .dusk: return "落日"
        case .night: return "夜航"
        case .paper: return "纸页"
        }
    }
}

final class DesktopModel: ObservableObject {
    @Published private(set) var theme: DesktopTheme
    @Published private(set) var glassScene: DesktopGlassScene
    private let themeDefaults: UserDefaults

    init(themeDefaults: UserDefaults = .standard) {
        self.themeDefaults = themeDefaults
        theme = DesktopTheme(rawValue: themeDefaults.string(forKey: "desktopTheme") ?? "") ?? .classic
        glassScene = DesktopGlassScene(rawValue: themeDefaults.string(forKey: "desktopGlassScene") ?? "") ?? .celadon
    }

    func selectTheme(_ rawValue: String?) {
        guard let rawValue else { return }
        let selection = DesktopTheme(rawValue: rawValue) ?? .classic
        if theme != selection { theme = selection }
        themeDefaults.set(selection.rawValue, forKey: "desktopTheme")
    }

    func selectGlassScene(_ rawValue: String?) {
        guard let rawValue else { return }
        let selection = DesktopGlassScene(rawValue: rawValue) ?? .celadon
        if glassScene != selection { glassScene = selection }
        themeDefaults.set(selection.rawValue, forKey: "desktopGlassScene")
    }

    @Published var title = "Likeit"
    @Published var artist = "网易云音乐 · 沉浸桌面"
    @Published var lyric = ""
    @Published var previousLine = ""
    @Published var nextLine = ""
    @Published var timedLyric: AttributedString?
    @Published var translation = ""
    @Published var plainLyrics: String?
    @Published var status = "等待网易云歌曲信息"
    @Published var audioStatus = ""
    @Published var canRetryAudio = false
    @Published var progress = 0.0
    @Published var low = 0.0
    @Published var mid = 0.0
    @Published var high = 0.0
}

struct DesktopView: View {
    @ObservedObject var model: DesktopModel
    let retryAudio: () -> Void
    let exit: () -> Void

    var body: some View {
        if model.theme == .glass {
            glass
        } else {
            classic
        }
    }

    private var classic: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                LinearGradient(colors: [Color(red: 0.025, green: 0.035, blue: 0.055), Color(red: 0.065, green: 0.095, blue: 0.13), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack {
                    speaker(size: min(size.width * 0.34, size.height * 0.65))
                    Spacer(minLength: size.width * 0.18)
                    speaker(size: min(size.width * 0.34, size.height * 0.65))
                }.padding(.horizontal, -size.width * 0.06).opacity(0.72)
                if let plain = model.plainLyrics {
                    ScrollView {
                        Text(plain).font(.system(size: 28, weight: .regular)).lineSpacing(12)
                            .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(24)
                    }.frame(width: size.width * 0.62, height: size.height * 0.60)
                        .accessibilityLabel("未同步歌词")
                } else {
                    VStack(spacing: 16) {
                        Text(model.previousLine).font(.system(size: 23, weight: .light)).foregroundStyle(.white.opacity(0.35)).lineLimit(2).frame(height: 58)
                        (model.timedLyric.map { Text($0) } ?? Text(model.lyric.isEmpty ? model.title : model.lyric))
                            .font(.system(size: min(104, max(64, size.width * 0.065)), weight: .medium, design: .rounded))
                            .multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.24)
                            .foregroundStyle(.white.opacity(0.96)).frame(height: size.height * 0.30)
                            .shadow(color: .black, radius: 22)
                        if !model.translation.isEmpty {
                            Text(model.translation).font(.system(size: 24)).foregroundStyle(.white.opacity(0.8))
                                .multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.65)
                        }
                        Text(model.nextLine).font(.system(size: 23, weight: .light)).foregroundStyle(.white.opacity(0.35)).lineLimit(2).frame(height: 58)
                    }.frame(width: size.width * 0.62)
                }
                VStack {
                    HStack {
                        Text("LIKEIT / MUSIC ROOM").font(.system(size: 12, weight: .medium, design: .monospaced)).tracking(3).foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        themeSelector
                        exitButton
                    }
                    Spacer()
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.title).font(.system(size: 20, weight: .medium)).lineLimit(2)
                            Text(model.artist).font(.system(size: 14)).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
                            ProgressView(value: model.progress).tint(.white.opacity(0.6)).frame(width: min(300, size.width * 0.25))
                        }
                        Spacer(minLength: 30)
                        VStack(alignment: .trailing, spacing: 6) {
                            Text(model.status)
                            Text(model.audioStatus)
                            if model.canRetryAudio {
                                Button("重试音频", action: retryAudio).buttonStyle(.bordered).accessibilityLabel("重试系统音频采集")
                            }
                        }.font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.trailing)
                    }
                }.padding(40)
            }.foregroundStyle(.white)
        }.ignoresSafeArea().preferredColorScheme(.dark)
    }

    private var themeSelector: some View {
        Picker("音响主题", selection: Binding(get: { model.theme }, set: { model.selectTheme($0.rawValue) })) {
            ForEach(DesktopTheme.allCases, id: \.self) { Text($0.title).tag($0) }
        }.pickerStyle(.segmented).frame(width: 210).accessibilityLabel("音响主题")
    }

    private var exitButton: some View {
        Button(action: exit) {
            Text("退出 · Esc").font(.system(size: 14, weight: .medium)).padding(.horizontal, 20).padding(.vertical, 12)
        }.buttonStyle(.plain).background(.white.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(.primary.opacity(0.2))).accessibilityLabel("退出沉浸桌面")
    }

    private var glass: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let palette = model.glassScene
            let margin = min(40.0, size.width * 0.035)
            ZStack {
                glassPanel(size: size)
                VStack(spacing: 20) {
                    HStack {
                        Text("LIKEIT").font(.system(size: 12, weight: .medium, design: .monospaced)).tracking(2)
                            .foregroundStyle(palette.ink.opacity(0.65)).lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 16)
                        themeSelector
                        Picker("透明场景", selection: Binding(get: { model.glassScene }, set: { model.selectGlassScene($0.rawValue) })) {
                            ForEach(DesktopGlassScene.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).frame(width: 240).accessibilityLabel("透明音响场景")
                        exitButton
                    }
                    Spacer(minLength: 0)
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(model.title).font(.system(size: 19, weight: .semibold)).lineLimit(2)
                            Text(model.artist).font(.system(size: 13)).foregroundStyle(palette.ink.opacity(0.7)).lineLimit(2)
                            ProgressView(value: model.progress).tint(palette.ink.opacity(0.65)).frame(maxWidth: 300)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .trailing, spacing: 8) {
                            Text(model.status)
                            Text(model.audioStatus)
                            if model.canRetryAudio {
                                Button("重试音频", action: retryAudio).buttonStyle(.bordered).accessibilityLabel("重试系统音频采集")
                            }
                        }.font(.system(size: 12)).multilineTextAlignment(.trailing)
                            .foregroundStyle(palette.ink.opacity(0.8)).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }.padding(margin)
            }.foregroundStyle(palette.ink)
                .preferredColorScheme(palette == .night ? .dark : .light)
        }.ignoresSafeArea()
    }

    private func glassPanel(size: CGSize) -> some View {
        let width = size.width, height = size.height
        let driverSize = min(width * 0.175, height * 0.28)
        let scene = model.glassScene
        return ZStack {
            LinearGradient(colors: scene.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            glassScenery(size: CGSize(width: width, height: height))
            VStack {
                Spacer()
                LinearGradient(colors: [.clear, Color(red: 0.48, green: 0.34, blue: 0.21).opacity(0.5), Color(red: 0.33, green: 0.22, blue: 0.13).opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    .frame(height: height * 0.09)
            }
            glassDriver(size: driverSize).position(x: width * 0.12, y: height * 0.24)
            glassDriver(size: driverSize).position(x: width * 0.80, y: height * 0.72)
            glassLyrics(size: CGSize(width: width, height: height))
            LinearGradient(stops: [.init(color: .white.opacity(0.17), location: 0), .init(color: .white.opacity(0.17), location: 0.13), .init(color: .clear, location: 0.133), .init(color: .clear, location: 0.37), .init(color: .white.opacity(0.07), location: 0.373), .init(color: .white.opacity(0.07), location: 0.45), .init(color: .clear, location: 0.453)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .allowsHitTesting(false).accessibilityHidden(true)
        }.frame(width: width, height: height).clipped()
            .overlay(Rectangle().strokeBorder(Color(white: 0.045), lineWidth: max(6, width * 0.005)).allowsHitTesting(false))
    }

    private func glassLyrics(size: CGSize) -> some View {
        let ink = model.glassScene.ink
        let height = size.height * 0.68
        return Group {
            if let plain = model.plainLyrics {
                ScrollView {
                    Text(plain).font(.system(size: max(19, size.width * 0.028), weight: .semibold)).lineSpacing(10)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                }.frame(width: size.width * 0.48, height: height * 0.77)
                    .accessibilityLabel("未同步歌词")
            } else {
                VStack(alignment: .leading, spacing: height * 0.02) {
                    Text(model.previousLine).font(.system(size: max(16, size.width * 0.023), weight: .medium))
                        .foregroundStyle(ink.opacity(0.65)).lineLimit(2).minimumScaleFactor(0.65)
                        .frame(height: height * 0.12, alignment: .bottomLeading)
                    (model.timedLyric.map { Text(glassHighlightedText($0, ink: ink)) } ?? Text(model.lyric.isEmpty ? model.title : model.lyric))
                        .font(.system(size: size.width * 0.081, weight: .black, design: .default))
                        .lineLimit(4).minimumScaleFactor(0.22).tracking(-0.5)
                        .frame(maxWidth: .infinity, alignment: .leading).frame(height: height * 0.38)
                    if !model.translation.isEmpty {
                        Text(model.translation).font(.system(size: max(16, size.width * 0.025), weight: .medium))
                            .foregroundStyle(ink.opacity(0.85)).lineLimit(3).minimumScaleFactor(0.55)
                            .frame(maxHeight: height * 0.14)
                    }
                    Text(model.nextLine).font(.system(size: max(16, size.width * 0.023), weight: .medium))
                        .foregroundStyle(ink.opacity(0.65)).lineLimit(2).minimumScaleFactor(0.65)
                        .frame(height: height * 0.12, alignment: .topLeading)
                }.frame(width: size.width * 0.48, height: height * 0.82)
            }
        }.foregroundStyle(ink).multilineTextAlignment(.leading)
            .position(x: size.width * 0.46, y: size.height * 0.47)
    }

    private func glassScenery(size: CGSize) -> some View {
        Canvas { context, canvas in
            switch model.glassScene {
            case .celadon:
                for (x, y, radius) in [(0.2, 0.3, 0.35), (0.75, 0.65, 0.4), (0.5, 0.1, 0.25)] {
                    let center = CGPoint(x: canvas.width * x, y: canvas.height * y)
                    let r = canvas.height * radius
                    context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .radialGradient(Gradient(colors: [.white.opacity(0.24), .clear]), center: center, startRadius: 0, endRadius: r))
                }
            case .dusk:
                let sun = CGRect(x: canvas.width * 0.62, y: canvas.height * 0.18, width: canvas.height * 0.46, height: canvas.height * 0.46)
                context.fill(Path(ellipseIn: sun), with: .color(Color(red: 1, green: 0.91, blue: 0.71).opacity(0.45)))
            case .night:
                for index in 0..<48 {
                    let x = Double((index * 73 + 19) % 101) / 101 * canvas.width
                    let y = Double((index * 37 + 11) % 97) / 97 * canvas.height * 0.85
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(.white.opacity(0.35)))
                }
            case .paper:
                for index in 0..<32 {
                    let x = Double(index) * canvas.width / 32
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: canvas.height))
                    context.stroke(line, with: .color(.black.opacity(0.025)), lineWidth: 1)
                }
            }
        }.frame(width: size.width, height: size.height).allowsHitTesting(false).accessibilityHidden(true)
    }

    private func glassDriver(size: Double) -> some View {
        ZStack {
            Circle().strokeBorder(Color(white: 0.045), lineWidth: size * 0.19)
                .shadow(color: .black.opacity(0.35), radius: size * 0.07, y: size * 0.035)
            ForEach(0..<4) { ring in
                Circle().stroke(Color(white: ring.isMultiple(of: 2) ? 0.17 : 0.055), lineWidth: size * 0.024)
                    .padding(Double(ring) * size * 0.033 + size * 0.02)
            }
            Circle().fill(RadialGradient(colors: [.white.opacity(0.38), .clear, .black.opacity(0.35)], center: .topLeading, startRadius: 0, endRadius: size * 0.65))
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 2)).padding(size * 0.19)
            ForEach(0..<4) { ring in
                Circle().stroke(.white.opacity(0.16 + model.mid * 0.2), lineWidth: 1).padding(size * (0.23 + Double(ring) * 0.065))
            }
            Ellipse().fill(.white.opacity(0.65 + model.high * 0.3)).frame(width: size * 0.18, height: size * 0.10)
                .rotationEffect(.degrees(-22)).offset(x: -size * 0.015, y: size * 0.11).blur(radius: 0.6)
        }.frame(width: size, height: size).scaleEffect(1 + model.low * 0.035)
            .accessibilityHidden(true).allowsHitTesting(false)
    }

    private func speaker(size: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30).fill(.white.opacity(0.018)).overlay(RoundedRectangle(cornerRadius: 30).stroke(LinearGradient(colors: [.white.opacity(0.26), .clear, .white.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            ForEach(0..<7) { ring in
                Circle().stroke(LinearGradient(colors: [.white.opacity(0.08 + model.mid * 0.2), .white.opacity(0.015), .cyan.opacity(0.07 + model.high * 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: ring == 0 ? 3 : 1)
                    .padding(Double(ring) * size * 0.044 + size * 0.07)
            }
            Circle().fill(RadialGradient(colors: [.white.opacity(0.025), .black.opacity(0.75), .white.opacity(0.09)], center: .center, startRadius: 0, endRadius: size * 0.27))
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1)).padding(size * 0.25)
                .scaleEffect(1 + model.low * 0.1)
            Circle().fill(.white.opacity(0.07)).frame(width: size * 0.12).blur(radius: 5)
        }.frame(width: size, height: size * 1.22)
    }
}

// Only parser-recorded ranges may receive timing; all other text stays unchanged.
func communityHighlightedText(_ line: CommunityLyricLine, at position: Double) -> AttributedString {
    var result = AttributedString(), cursor = line.text.startIndex
    let length = line.text.utf16.count
    for word in line.words {
        guard let recorded = word.utf16Range, recorded.location >= 0, recorded.location <= length,
              recorded.length > 0, recorded.length <= length - recorded.location,
              let range = Range(recorded, in: line.text), range.lowerBound >= cursor,
              line.text[range] == word.text else { continue }
        result.append(AttributedString(String(line.text[cursor..<range.lowerBound])))
        var text = AttributedString(String(line.text[range]))
        text.foregroundColor = .white.opacity(0.35 + 0.65 * communityWordProgress(word, at: position))
        result.append(text)
        cursor = range.upperBound
    }
    result.append(AttributedString(String(line.text[cursor...])))
    return result
}

private extension DesktopGlassScene {
    var colors: [Color] {
        switch self {
        case .celadon: return [Color(red: 0.553, green: 0.694, blue: 0.663), Color(red: 0.4, green: 0.545, blue: 0.522)]
        case .dusk: return [Color(red: 0.961, green: 0.639, blue: 0.408), Color(red: 0.812, green: 0.29, blue: 0.42)]
        case .night: return [Color(red: 0.063, green: 0.165, blue: 0.278), Color(red: 0.114, green: 0.31, blue: 0.451)]
        case .paper: return [Color(red: 0.914, green: 0.871, blue: 0.769), Color(red: 0.824, green: 0.761, blue: 0.616)]
        }
    }
    var ink: Color {
        switch self {
        case .celadon: return Color(red: 0.071, green: 0.09, blue: 0.094)
        case .dusk: return Color(red: 0.231, green: 0.051, blue: 0.11)
        case .night: return Color(red: 0.839, green: 0.941, blue: 1)
        case .paper: return Color(red: 0.102, green: 0.086, blue: 0.071)
        }
    }

}

// Recolor a presentation copy; timing, text and the session's attributes stay intact.
private func glassHighlightedText(_ lyric: AttributedString, ink: Color) -> AttributedString {
    var result = lyric
    for run in lyric.runs {
        let opacity = run.foregroundColor.map { NSColor($0).alphaComponent } ?? 1
        result[run.range].foregroundColor = ink.opacity(0.6 + 0.4 * Double(opacity))
    }
    return result
}
