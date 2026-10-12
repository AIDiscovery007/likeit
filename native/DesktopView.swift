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

struct DesktopLyricCue: Hashable {
    let trackKey: String
    let index: Int
    let start: Double
}

struct DesktopLyricSample: Equatable {
    let position: Double
    let sampledAt: Double
    let rate: Double
}

struct DesktopGlassLyricLine: Equatable {
    let cue: DesktopLyricCue
    let text: String
}

final class DesktopModel: ObservableObject {
    @Published var glassPage: [DesktopGlassLyricLine] = []
    @Published var lyricCue: DesktopLyricCue?
    @Published var lyricPosition: Double?
    @Published var lyricSample: DesktopLyricSample?
    @Published var motionEnabled = false
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
    private static let logo = Bundle.main.url(forResource: "Likeit", withExtension: "icns").flatMap(NSImage.init(contentsOf:))
    @ObservedObject var model: DesktopModel
    let retryAudio: () -> Void
    let exit: () -> Void

    @ViewBuilder private var brandIcon: some View {
        if let logo = Self.logo {
            Image(nsImage: logo).resizable().scaledToFit().frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityHidden(true)
        }
    }

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
                        brandIcon
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
                    HStack(spacing: 10) {
                        brandIcon
                        Text("LIKEIT").font(.system(size: 12, weight: .medium, design: .monospaced)).tracking(2)
                            .foregroundStyle(palette.ink.opacity(0.65)).lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 16)
                        Picker("音响主题", selection: Binding(get: { model.theme }, set: { model.selectTheme($0.rawValue) })) {
                            ForEach(DesktopTheme.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).controlSize(.small).labelsHidden().frame(width: 180)
                        HStack(spacing: 2) {
                            ForEach(DesktopGlassScene.allCases, id: \.self) { scene in
                                Button { model.selectGlassScene(scene.rawValue) } label: {
                                    HStack(spacing: 5) {
                                        Circle().fill(scene.colors[0]).overlay(Circle().strokeBorder(palette.ink.opacity(0.25), lineWidth: 0.5)).frame(width: 7, height: 7)
                                        Text(scene.title).font(.system(size: 11, weight: model.glassScene == scene ? .semibold : .regular))
                                    }.padding(.horizontal, 9).frame(height: 30)
                                        .background(palette.ink.opacity(model.glassScene == scene ? 0.10 : 0), in: RoundedRectangle(cornerRadius: 5))
                                }.buttonStyle(.plain).accessibilityLabel("透明场景：" + scene.title)
                                    .accessibilityAddTraits(model.glassScene == scene ? .isSelected : [])
                            }
                        }.padding(2).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(palette.ink.opacity(0.16), lineWidth: 0.5))
                        Button(action: exit) {
                            Text("退出 · Esc").font(.system(size: 11, weight: .medium)).padding(.horizontal, 14).frame(height: 34)
                        }.buttonStyle(.plain).background(.white.opacity(0.07), in: Capsule())
                            .overlay(Capsule().strokeBorder(palette.ink.opacity(0.2), lineWidth: 0.5)).accessibilityLabel("退出沉浸桌面")
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
        DesktopGlassPanel(model: model, size: size)
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

private struct DesktopGlassPanel: View {
    private struct AudioBlend {
        let from: SIMD3<Double>
        let to: SIMD3<Double>
        let started = Date()
        func value(at date: Date) -> SIMD3<Double> {
            let progress = min(1, max(0, date.timeIntervalSince(started)) / (1.0 / 30))
            return from + (to - from) * SIMD3(repeating: progress)
        }
    }
    @ObservedObject var model: DesktopModel
    let size: CGSize
    // Short presentation interpolation only; never feeds the capture or lyric pipelines.
    @State private var audioBlend: AudioBlend?
    @State private var positionObservedAt = Date()

    private var bands: SIMD3<Double> {
        model.motionEnabled ? SIMD3(model.low, model.mid, model.high) : .zero
    }
    private var drifting: Bool {
        bands != .zero && model.lyricPosition != nil && (model.glassScene == .celadon || model.glassScene == .night)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !drifting && audioBlend == nil)) { context in
            let value = bands == .zero ? .zero : audioBlend?.value(at: context.date) ?? bands
            let phase = model.lyricPosition.map { $0 + min(0.1, max(0, context.date.timeIntervalSince(positionObservedAt))) } ?? 0
            panel(bands: value, phase: drifting ? phase : 0, moving: drifting)
        }
        .onChange(of: bands) { old, value in
            audioBlend = value == .zero ? nil : AudioBlend(from: audioBlend?.value(at: .now) ?? old, to: value)
        }
        .onChange(of: model.lyricPosition, initial: true) { _, _ in positionObservedAt = .now }
        .onDisappear { audioBlend = nil }
        .task(id: audioBlend?.started) {
            guard let started = audioBlend?.started else { return }
            try? await Task.sleep(for: .milliseconds(34))
            guard !Task.isCancelled, audioBlend?.started == started else { return }
            audioBlend = nil
        }
    }

    private func panel(bands: SIMD3<Double>, phase: Double, moving: Bool) -> some View {
        let width = size.width, height = size.height
        let driverSize = min(width * 0.175, height * 0.28)
        let scene = model.glassScene
        return ZStack {
            LinearGradient(colors: scene.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            glassScenery(bands: bands, phase: phase, moving: moving)
            VStack {
                Spacer()
                LinearGradient(colors: [.clear, Color(red: 0.48, green: 0.34, blue: 0.21).opacity(0.5), Color(red: 0.33, green: 0.22, blue: 0.13).opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    .frame(height: height * 0.09).blendMode(.multiply)
            }
            DesktopGlassPoster(model: model, size: size)
            glassDriver(size: driverSize, bands: bands).position(x: width * 0.1125, y: height * 0.24)
            glassDriver(size: driverSize, bands: bands).position(x: width * 0.7275, y: height * 0.64)
            LinearGradient(stops: [.init(color: .white.opacity(0.17), location: 0), .init(color: .white.opacity(0.17), location: 0.13), .init(color: .clear, location: 0.133), .init(color: .clear, location: 0.37), .init(color: .white.opacity(0.07), location: 0.373), .init(color: .white.opacity(0.07), location: 0.45), .init(color: .clear, location: 0.453)], startPoint: UnitPoint(x: 0, y: 0.25), endPoint: UnitPoint(x: 1, y: 0.65))
                .allowsHitTesting(false).accessibilityHidden(true)
        }.frame(width: width, height: height).clipped()
            .overlay(Rectangle().strokeBorder(.black.opacity(0.12), lineWidth: 28).blur(radius: 18).allowsHitTesting(false))
            .overlay(Rectangle().inset(by: max(6, width * 0.005)).strokeBorder(.white.opacity(0.3), lineWidth: 1).allowsHitTesting(false))
            .overlay(Rectangle().strokeBorder(Color(white: 0.045), lineWidth: max(6, width * 0.005)).allowsHitTesting(false))
    }

    private func glassScenery(bands: SIMD3<Double>, phase: Double, moving: Bool) -> some View {
        Canvas { context, canvas in
            drawGlassScenery(context: &context, size: canvas, bands: bands, phase: phase, moving: moving)
        }.frame(width: size.width, height: size.height).allowsHitTesting(false).accessibilityHidden(true)
    }

    private func drawGlassScenery(context: inout GraphicsContext, size canvas: CGSize, bands: SIMD3<Double>, phase: Double, moving: Bool) {
        let low = min(1, bands.x * 2), mid = bands.y, high = bands.z
        let energy = (low + mid + high) / 3
        switch model.glassScene {
        case .celadon:
            for (index, blob) in [(0.2, 0.3, 0.35), (0.75, 0.65, 0.4), (0.5, 0.1, 0.25)].enumerated() {
                let offset = Double(index) * 2
                let x = moving ? sin(phase * 0.2 + offset) * 0.06 : 0
                let y = moving ? cos(phase * 0.17 + offset) * 0.05 : 0
                let center = CGPoint(x: canvas.width * (blob.0 + x), y: canvas.height * (blob.1 + y))
                let radius = canvas.height * blob.2 * (1 + low * 0.07)
                context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .radialGradient(Gradient(colors: [.white.opacity(0.22), .clear]), center: center, startRadius: 0, endRadius: radius))
            }
        case .dusk:
            let radius = canvas.height * 0.27 * (1 + low * 0.08)
            let sun = CGRect(x: canvas.width * 0.72 - radius, y: canvas.height * 0.60 - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: sun), with: .color(Color(red: 1, green: 0.91, blue: 0.71).opacity(0.42)))
            context.blendMode = .clear
            for stripe in 0..<5 {
                let y = sun.midY + Double(stripe) * radius * 0.17
                context.fill(Path(CGRect(x: sun.minX, y: y, width: sun.width, height: radius * (0.025 + Double(stripe) * 0.018))), with: .color(.black))
            }
        case .night:
            for index in 0..<70 {
                let x = Double((index * 73 + 19) % 101) / 101 * canvas.width
                let y = Double((index * 37 + 11) % 97) / 97 * canvas.height * 0.85
                let shimmer = moving ? (0.5 + 0.5 * sin(phase * (0.9 + Double(index % 6) * 0.4) + Double(index))) * (0.1 + high * 0.15) : 0
                let diameter = 1.2 + Double(index % 3) * 0.45
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)), with: .color(.white.opacity(0.18 + shimmer)))
            }
            for wave in 0..<3 {
                var path = Path()
                for step in 0...120 {
                    let x = Double(step) / 120
                    let ripple = sin(x * 12 + Double(wave)) * 0.004 + sin(x * 16 + phase * (1.5 + Double(wave) * 0.45) + Double(wave)) * energy * 0.028
                    let point = CGPoint(x: x * canvas.width, y: canvas.height * (0.86 + Double(wave) * 0.03 + ripple))
                    if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                context.stroke(path, with: .color(.white.opacity(0.10 + mid * 0.12)), lineWidth: 1.5)
            }
        case .paper:
            let anchors = [bands.x, mid, high]
            let width = canvas.width / 40
            for index in 0..<40 {
                let x = Double(index) * width
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: canvas.height))
                context.stroke(line, with: .color(.black.opacity(0.025)), lineWidth: 1)
                // A continuous envelope between three real bands, not a full FFT spectrum.
                let position = Double(index) / 39 * 2
                let left = min(1, Int(position)), fraction = position - Double(left)
                let blend = fraction * fraction * (3 - 2 * fraction)
                let value = anchors[left] + (anchors[left + 1] - anchors[left]) * blend
                let height = pow(value, 1.4) * canvas.height * 0.45
                context.fill(Path(CGRect(x: x + width * 0.14, y: canvas.height * 0.92 - height, width: width * 0.72, height: height)), with: .color(.black.opacity(0.12)))
            }
        }
    }

    private func glassDriver(size: Double, bands: SIMD3<Double>) -> some View {
        // Fixed 2× perceptual gain keeps a moderate true bass input visible; no peak tracking.
        let low = min(1, bands.x * 2), high = bands.z
        return ZStack {
            ZStack {
                Circle().strokeBorder(Color(white: 0.045), lineWidth: size * 0.19)
                    .shadow(color: .black.opacity(0.35), radius: size * 0.07, y: size * 0.035)
                ForEach(0..<4) { ring in
                    Circle().stroke(Color(white: ring.isMultiple(of: 2) ? 0.17 : 0.055), lineWidth: size * 0.024)
                        .padding(Double(ring) * size * 0.033 + size * 0.02)
                }
            }.scaleEffect(1 + low * 0.012)
            ZStack {
                Circle().fill(RadialGradient(colors: [.white.opacity(0.28), .clear, .black.opacity(0.3)], center: .topLeading, startRadius: 0, endRadius: size * 0.65))
                    .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1)).padding(size * 0.19)
                ForEach(0..<4) { ring in
                    Circle().stroke(.white.opacity(0.16), lineWidth: 1).padding(size * (0.23 + Double(ring) * 0.065))
                }
                Ellipse().fill(.white.opacity(0.62 + high * 0.15)).frame(width: size * 0.18, height: size * 0.10)
                    .rotationEffect(.degrees(-22)).offset(x: -size * 0.015, y: size * 0.11)
            }.scaleEffect(1 + low * 0.06)
        }.frame(width: size, height: size).accessibilityHidden(true).allowsHitTesting(false)
    }
}

// Fixed row bands avoid the two fixed driver bounds, including their maximum travel.
// Measurement runs only when page content or viewport size changes.
private struct GlassPosterLayout {
    struct Line {
        let cue: DesktopLyricCue
        let text: AttributedString
        let x: CGFloat
        let width: CGFloat
        let textWidth: CGFloat
        let height: CGFloat
        let contentHeight: CGFloat
    }
    var lines: [Line] = []

    init(page: [DesktopGlassLyricLine] = [], size: CGSize = .zero) {
        guard !page.isEmpty, size.width > 0 else { return }
        let stage = CGRect(x: size.width * 0.04, y: size.height * 0.15, width: size.width * 0.92, height: size.height * 0.61)
        let rowHeight = stage.height / CGFloat(page.count)
        let diameter = min(size.width * 0.175, size.height * 0.28) * 1.012
        let drivers = [(0.1125, 0.24), (0.7275, 0.64)].map { x, y in
            CGRect(x: size.width * x - diameter / 2, y: size.height * y - diameter / 2, width: diameter, height: diameter).insetBy(dx: -20, dy: -16)
        }
        func prepare(_ text: String, _ pointSize: CGFloat) -> (AttributedString, NSAttributedString) {
            var display = AttributedString()
            let measured = NSMutableAttributedString(string: "")
            let latin = NSFont(name: "Impact", size: pointSize) ?? .systemFont(ofSize: pointSize, weight: .black)
            let other = NSFont.systemFont(ofSize: pointSize, weight: .black)
            for character in text {
                let font = character.unicodeScalars.allSatisfy { $0.value < 0x0250 } ? latin : other
                var run = AttributedString(String(character))
                run.font = Font(font)
                display.append(run)
                measured.append(NSAttributedString(string: String(character), attributes: [.font: font]))
            }
            return (display, measured)
        }
        lines = page.enumerated().map { index, line in
            let top = stage.minY + CGFloat(index) * rowHeight
            var intervals = [stage.minX...stage.maxX]
            for driver in drivers where driver.minY < top + rowHeight && driver.maxY > top {
                intervals = intervals.flatMap { interval -> [ClosedRange<CGFloat>] in
                    guard driver.minX < interval.upperBound && driver.maxX > interval.lowerBound else { return [interval] }
                    var remaining: [ClosedRange<CGFloat>] = []
                    if driver.minX > interval.lowerBound { remaining.append(interval.lowerBound...driver.minX) }
                    if driver.maxX < interval.upperBound { remaining.append(driver.maxX...interval.upperBound) }
                    return remaining
                }
            }
            let interval = intervals.max { $0.upperBound - $0.lowerBound < $1.upperBound - $1.lowerBound } ?? stage.minX...stage.maxX
            let width = interval.upperBound - interval.lowerBound
            func bounds(_ value: NSAttributedString) -> CGRect {
                value.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
            }
            let maximum = min(size.width * 0.24, rowHeight * 0.95)
            let natural = prepare(line.text, maximum).1
            var pointSize = max(24, maximum * min(1, width / max(1, natural.size().width)))
            for _ in 0..<3 {
                let height = ceil(bounds(prepare(line.text, pointSize).1).height) + 4
                guard height > rowHeight else { break }
                pointSize = max(24, pointSize * rowHeight / height)
            }
            let (text, measured) = prepare(line.text, pointSize)
            let rect = bounds(measured)
            return Line(cue: line.cue, text: text, x: interval.lowerBound - stage.minX, width: width,
                        textWidth: min(width, ceil(rect.width)), height: rowHeight, contentHeight: ceil(rect.height) + 4)
        }
    }
}

private struct DesktopGlassPoster: View {
    private struct Input: Equatable {
        let page: [DesktopGlassLyricLine]
        let cue: DesktopLyricCue?
        let sample: DesktopLyricSample?
        let enabled: Bool
    }
    private struct Arrival {
        let id = UUID()
        let cue: DesktopLyricCue
        let started = Date()
        var departing: GlassPosterLayout?
    }
    @ObservedObject var model: DesktopModel
    let size: CGSize
    // Input is the last rendered observation, never a second lyric clock.
    @State private var previous: Input?
    // At most one 500ms entrance and one 320ms outgoing page; cancelled together.
    @State private var arrival: Arrival?
    @State private var layout = GlassPosterLayout()

    private var stage: CGSize { CGSize(width: size.width * 0.92, height: size.height * 0.61) }
    private var driverRadius: CGFloat { min(size.width * 0.175, size.height * 0.28) * 1.012 / 2 }
    private var readingInset: CGFloat { size.width * 0.0725 + driverRadius + 20 }
    private var readingWidth: CGFloat { max(1, size.width * 0.615 - driverRadius * 2 - 40) }
    private var input: Input { Input(page: model.glassPage, cue: model.lyricCue, sample: model.lyricSample, enabled: model.motionEnabled) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let plain = model.plainLyrics {
                    ScrollView {
                        Text(plain).font(.system(size: max(24, size.width * 0.022), weight: .semibold))
                            .lineSpacing(10).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(width: readingWidth).padding(.leading, readingInset)
                        .frame(width: stage.width, alignment: .leading).accessibilityLabel("未同步歌词")
                } else if !model.glassPage.isEmpty {
                    TimelineView(.animation(minimumInterval: 1.0 / 60, paused: arrival == nil)) { context in
                        let elapsed = arrival.map { max(0, context.date.timeIntervalSince($0.started)) } ?? 1
                        ZStack(alignment: .topLeading) {
                            if let departing = arrival?.departing, model.motionEnabled {
                                page(departing, elapsed: 1, departing: true)
                                    .opacity(0.24 * (1 - UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.25, y: 0.1), endControlPoint: UnitPoint(x: 0.25, y: 1)).value(at: min(1, elapsed / 0.32))))
                                    .allowsHitTesting(false).accessibilityHidden(true)
                            }
                            page(layout, elapsed: elapsed)
                        }
                    }
                } else {
                    ScrollView {
                        Text(model.lyric.isEmpty ? model.title : model.lyric)
                            .font(.system(size: min(80, readingWidth * 0.14), weight: .black))
                            .frame(maxWidth: .infinity, minHeight: stage.height, alignment: .leading)
                    }.frame(width: readingWidth).padding(.leading, readingInset)
                        .frame(width: stage.width, alignment: .leading)
                }
            }.frame(width: stage.width, height: stage.height)
            ScrollView {
                Text(model.translation).font(.system(size: min(24, max(16, size.width * 0.017)), weight: .medium))
                    .foregroundStyle(model.glassScene.ink.opacity(0.78))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(width: size.width * 0.6875 - driverRadius - 20, height: size.height * 0.075)
                .padding(.top, size.height * 0.015)
        }.foregroundStyle(model.glassScene.ink)
            .frame(width: stage.width, alignment: .leading)
            .position(x: size.width * 0.5, y: size.height * 0.5)
            .onChange(of: input, initial: true) { _, value in receive(value) }
            .onChange(of: size) { _, _ in
                arrival = nil
                layout = GlassPosterLayout(page: model.glassPage, size: size)
            }
            .onDisappear { arrival = nil; previous = nil }
            .task(id: arrival?.id) {
                guard let id = arrival?.id else { return }
                try? await Task.sleep(for: .milliseconds(320))
                guard !Task.isCancelled, arrival?.id == id else { return }
                arrival?.departing = nil
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled, arrival?.id == id else { return }
                arrival = nil
            }
    }

    private func receive(_ value: Input) {
        let changed = previous?.page != value.page
        let oldLayout = layout
        if changed { layout = GlassPosterLayout(page: value.page, size: size) }
        var continuous = false
        if value.enabled, previous?.enabled == true, let sample = value.sample, let old = previous?.sample,
           sample.rate == old.rate, sample.rate > 0 {
            let interval = sample.sampledAt - old.sampledAt
            let advance = sample.position - old.position
            // Compare source samples; display scheduling must not masquerade as a seek.
            continuous = interval > 0 && interval <= 0.5 && advance >= 0 && abs(advance - old.rate * interval) <= 0.005
        }
        if value.cue != previous?.cue {
            if continuous, let cue = value.cue, let oldPosition = previous?.sample?.position,
               oldPosition < cue.start, value.sample.map({ $0.position >= cue.start }) == true,
               (previous?.cue.map { $0.trackKey == cue.trackKey && $0.index + 1 == cue.index } ?? (cue.index == 0)) {
                arrival = Arrival(cue: cue, departing: changed && !oldLayout.lines.isEmpty ? oldLayout : nil)
            } else {
                arrival = nil
            }
        } else if !continuous || changed {
            arrival = nil
        }
        previous = value
    }

    private func page(_ page: GlassPosterLayout, elapsed: Double, departing: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(page.lines, id: \.cue) { line in
                let visible = departing || (previous?.cue.map { $0.trackKey == line.cue.trackKey && $0.index >= line.cue.index } ?? false)
                let entering = !departing && model.motionEnabled && arrival?.cue == line.cue
                let opacity = entering ? UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.25, y: 0.1), endControlPoint: UnitPoint(x: 0.25, y: 1)).value(at: min(1, elapsed / 0.22)) : 1
                let travel = entering ? 1 - UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.2, y: 0.8), endControlPoint: UnitPoint(x: 0.2, y: 1)).value(at: min(1, elapsed / 0.5)) : 0
                Group {
                    if line.contentHeight > line.height {
                        ScrollView { Text(departing ? line.text : highlighted(line)).fixedSize(horizontal: false, vertical: true).frame(width: line.width, alignment: .leading) }
                    } else {
                        Text(departing ? line.text : highlighted(line)).fixedSize(horizontal: false, vertical: true).frame(width: line.width, alignment: .leading)
                    }
                }.frame(width: line.width, height: line.height, alignment: .leading)
                    .padding(.leading, line.x).frame(width: stage.width, alignment: .leading)
                    .opacity(visible ? opacity : 0).offset(x: -min(18, line.textWidth * 0.025) * travel)
                    .accessibilityHidden(!visible).allowsHitTesting(visible && !departing)
            }
        }
    }

    private func highlighted(_ line: GlassPosterLayout.Line) -> AttributedString {
        guard line.cue == model.lyricCue, let timed = model.timedLyric,
              String(timed.characters) == String(line.text.characters) else { return line.text }
        var result = line.text
        for run in timed.runs {
            let offset = timed.characters.distance(from: timed.startIndex, to: run.range.lowerBound)
            let length = timed.characters.distance(from: run.range.lowerBound, to: run.range.upperBound)
            let start = result.characters.index(result.startIndex, offsetBy: offset)
            let end = result.characters.index(start, offsetBy: length)
            let opacity = run.foregroundColor.map { NSColor($0).alphaComponent } ?? 1
            result[start..<end].foregroundColor = model.glassScene.ink.opacity(0.6 + 0.4 * Double(opacity))
        }
        return result
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
