import SwiftUI

final class DesktopModel: ObservableObject {
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
                        Button(action: exit) { Text("退出 · Esc").font(.system(size: 14, weight: .medium)).padding(.horizontal, 20).padding(.vertical, 12) }
                            .buttonStyle(.plain).background(.white.opacity(0.12), in: Capsule()).overlay(Capsule().stroke(.white.opacity(0.2))).accessibilityLabel("退出沉浸桌面")
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
        }.ignoresSafeArea()
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

// Find each timed word in the original line, preserving all intervening text.
func communityHighlightedText(_ line: CommunityLyricLine, at position: Double) -> AttributedString {
    var result = AttributedString(), cursor = line.text.startIndex
    for word in line.words {
        guard !word.text.isEmpty, let range = line.text.range(of: word.text, range: cursor..<line.text.endIndex) else { continue }
        result.append(AttributedString(String(line.text[cursor..<range.lowerBound])))
        var text = AttributedString(String(line.text[range]))
        text.foregroundColor = .white.opacity(0.35 + 0.65 * communityWordProgress(word, at: position))
        result.append(text)
        cursor = range.upperBound
    }
    result.append(AttributedString(String(line.text[cursor...])))
    return result
}
