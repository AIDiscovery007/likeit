import Foundation
import Accelerate

func desktopMotionEnabled(mode: String, reduceMotion: Bool?) -> Bool {
    mode == "always" || (mode == "system" && reduceMotion == false)
}

struct LyricLine: Codable { let time: Double; let text: String }

func parseLRC(_ text: String) -> [LyricLine] {
    guard text.utf8.count <= 1_048_576 else { return [] }
    let timestamp = try! NSRegularExpression(pattern: #"\[(\d+):([0-5]?\d)(?:\.(\d{1,3}))?\]"#)
    let offsetPattern = try! NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)
    let source = text as NSString
    let offset = offsetPattern.matches(in: text, range: NSRange(location: 0, length: source.length)).last.flatMap { Double(source.substring(with: $0.range(at: 1))) }.map { $0 / 1000 } ?? 0
    guard offset.isFinite else { return [] }
    var entries: [Double: [String]] = [:]
    var seen: [Double: Set<String>] = [:]
    for raw in text.components(separatedBy: .newlines) {
        let line = raw as NSString
        let matches = timestamp.matches(in: raw, range: NSRange(location: 0, length: line.length))
        guard let last = matches.last, matches.first?.range.location == 0 else { continue }
        let words = line.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)
        for match in matches {
            guard let minutes = Double(line.substring(with: match.range(at: 1))), let seconds = Double(line.substring(with: match.range(at: 2))) else { continue }
            let fraction = match.range(at: 3).location == NSNotFound ? 0 : (Double("0." + line.substring(with: match.range(at: 3))) ?? 0)
            let time = max(0, minutes * 60 + seconds + fraction + offset)
            guard time.isFinite else { continue }
            if seen[time, default: []].insert(words).inserted { entries[time, default: []].append(words) }
        }
    }
    return entries.keys.sorted().map { LyricLine(time: $0, text: entries[$0]!.joined(separator: "\n")) }
}

func activeLyricIndex(in lines: [LyricLine], at position: Double) -> Int? {
    guard position.isFinite, position >= 0 else { return nil }
    var low = 0, high = lines.count
    while low < high {
        let middle = (low + high) / 2
        if lines[middle].time <= position { low = middle + 1 } else { high = middle }
    }
    return low == 0 ? nil : low - 1
}

func playbackPosition(elapsed: Double, rate: Double, sampledAt: Double, now: Double, duration: Double) -> Double? {
    guard [elapsed, rate, sampledAt, now, duration].allSatisfy(\.isFinite), elapsed >= 0, duration > 0,
          (0...4).contains(rate), (0...5).contains(now - sampledAt) else { return nil }
    return min(duration, max(0, elapsed + (now - sampledAt) * rate))
}

struct TrackMetadata { let title: String; let artists: [String]; let album: String; let duration: Double }
struct SongCandidate { let id: String; let metadata: TrackMetadata }

private func normalized(_ text: String) -> String {
    text.precomposedStringWithCanonicalMapping.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

func matchedSongID(for track: TrackMetadata, candidates: [SongCandidate]) -> String? {
    func valid(_ value: TrackMetadata) -> Bool {
        !normalized(value.title).isEmpty && !normalized(value.album).isEmpty && !value.artists.isEmpty && value.artists.allSatisfy { !normalized($0).isEmpty } && value.duration.isFinite && value.duration > 0
    }
    guard valid(track) else { return nil }
    let artists = track.artists.map(normalized)
    let matches = candidates.filter { candidate in
        let value = candidate.metadata
        let otherArtists = value.artists.map(normalized)
        let validID = !candidate.id.isEmpty && candidate.id.utf8.allSatisfy { (48...57).contains($0) } && candidate.id.contains(where: { $0 != "0" })
        return validID && valid(value) && normalized(value.title) == normalized(track.title) && normalized(value.album) == normalized(track.album) && abs(value.duration - track.duration) <= 1 && (Set(artists) == Set(otherArtists) || (artists.count == 1 && artists[0] == otherArtists.joined(separator: " / ")))
    }
    let ids = Set(matches.map(\.id))
    return ids.count == 1 ? ids.first : nil
}

struct LyricState {
    private(set) var trackKey: String?
    private(set) var lines: [LyricLine] = []
    mutating func beginTrack(_ key: String?) {
        if trackKey != key { trackKey = key; lines = [] }
    }
    @discardableResult mutating func accept(_ lines: [LyricLine], for key: String) -> Bool {
        guard trackKey == key else { return false }
        self.lines = lines
        return true
    }
}

struct AudioFeatures { let rms: Double; let low: Double; let mid: Double; let high: Double }

private let spectrumLock = NSLock()
private var spectrumAnalyzers: [Int: SpectrumAnalyzer] = [:]

func analyzeAudio(samples: [Float], sampleRate: Double) -> AudioFeatures {
    let zero = AudioFeatures(rms: 0, low: 0, mid: 0, high: 0)
    guard !samples.isEmpty, sampleRate.isFinite, sampleRate > 0, samples.allSatisfy(\.isFinite) else { return zero }
    let rms = min(1, sqrt(samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)))
    guard rms > 0 else { return zero }
    var count = 2
    while count < min(samples.count, 16_384) { count *= 2 }
    spectrumLock.lock(); defer { spectrumLock.unlock() }
    if spectrumAnalyzers[count] == nil { spectrumAnalyzers[count] = SpectrumAnalyzer(count: count) }
    return spectrumAnalyzers[count]?.analyze(samples, sampleRate: sampleRate, rms: rms) ?? zero
}

private final class SpectrumAnalyzer {
    let count: Int
    let log2Count: vDSP_Length
    let setup: FFTSetup
    var real: [Float]
    var imaginary: [Float]
    var window: [Float]

    init?(count: Int) {
        self.count = count
        log2Count = vDSP_Length(log2(Double(count)))
        guard let setup = vDSP_create_fftsetup(log2Count, FFTRadix(kFFTRadix2)) else { return nil }
        self.setup = setup
        real = [Float](repeating: 0, count: count)
        imaginary = real
        window = real
        vDSP_hann_window(&window, vDSP_Length(count), Int32(vDSP_HANN_NORM))
    }
    deinit { vDSP_destroy_fftsetup(setup) }

    func analyze(_ samples: [Float], sampleRate: Double, rms: Double) -> AudioFeatures {
        for index in 0..<count {
            real[index] = index < samples.count ? min(1, max(-1, samples[index])) * window[index] : 0
            imaginary[index] = 0
        }
        real.withUnsafeMutableBufferPointer { real in
            imaginary.withUnsafeMutableBufferPointer { imaginary in
                var split = DSPSplitComplex(realp: real.baseAddress!, imagp: imaginary.baseAddress!)
                vDSP_fft_zip(setup, &split, 1, log2Count, FFTDirection(FFT_FORWARD))
            }
        }
        var low = 0.0, mid = 0.0, high = 0.0
        for bin in 1..<(count / 2) {
            let frequency = Double(bin) * sampleRate / Double(count)
            let energy = Double(real[bin]) * Double(real[bin]) + Double(imaginary[bin]) * Double(imaginary[bin])
            if frequency >= 20 && frequency < 250 { low += energy }
            else if frequency >= 250 && frequency < 2000 { mid += energy }
            else if frequency >= 2000 && frequency <= min(12000, sampleRate / 2) { high += energy }
        }
        func response(_ energy: Double) -> Double { min(1, sqrt(energy) * 4 / Double(count)) }
        return AudioFeatures(rms: rms, low: response(low), mid: response(mid), high: response(high))
    }
}
