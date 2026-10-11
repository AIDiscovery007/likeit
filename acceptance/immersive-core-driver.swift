import Foundation

@main
struct Acceptance {
    static func main() {
        var results: [[String: Any]] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            results.append(["name": name, "passed": condition()])
        }
        func near(_ a: Double, _ b: Double, _ epsilon: Double = 0.00001) -> Bool { abs(a - b) <= epsilon }
        func metadata(_ title: String = "A Song", _ artists: [String] = ["Artist"],
                      _ album: String = "Album", _ duration: Double = 180) -> TrackMetadata {
            TrackMetadata(title: title, artists: artists, album: album, duration: duration)
        }
        func candidate(_ id: String = "123", _ value: TrackMetadata = TrackMetadata(title: "A Song", artists: ["Artist"], album: "Album", duration: 180)) -> SongCandidate {
            SongCandidate(id: id, metadata: value)
        }
        func tone(_ frequency: Double, _ amplitude: Double = 0.5, _ rate: Double = 48000) -> [Float] {
            (0..<4096).map { Float(amplitude * sin(2 * Double.pi * frequency * Double($0) / rate)) }
        }
        func zero(_ f: AudioFeatures) -> Bool { f.rms == 0 && f.low == 0 && f.mid == 0 && f.high == 0 }
        func bounded(_ f: AudioFeatures) -> Bool {
            [f.rms, f.low, f.mid, f.high].allSatisfy { $0.isFinite && (0...1).contains($0) }
        }

        let basic = parseLRC("[ar:Artist]\n[00:02.500]Second\n[00:01.25]First\n[00:03]第三句")
        check("L01 sorted timestamp precisions and Unicode", basic.count == 3 && near(basic[0].time, 1.25) && basic[0].text == "First" && near(basic[1].time, 2.5) && basic[2].text == "第三句")
        let multi = parseLRC("[offset:250]\n[00:01][00:02.050]Again")
        check("L02 multiple time tags and global offset", multi.count == 2 && near(multi[0].time, 1.25) && near(multi[1].time, 2.3) && multi[1].text == "Again")
        let negative = parseLRC("[00:01]A\n[offset:-1500]\n[00:03]B")
        check("L03 negative offset applies globally and clamps", negative.count == 2 && negative[0].time == 0 && near(negative[1].time, 1.5))
        let duplicates = parseLRC("[00:01]A\n[00:01]A\n[00:01]翻译")
        check("L04 simultaneous text merges without duplicates", duplicates.count == 1 && duplicates[0].text == "A\n翻译")
        let blanks = parseLRC("[00:01]A\n[00:02]\n[00:03]B")
        check("L05 empty timed line clears previous sentence", blanks.count == 3 && blanks[1].text == "")
        let invalid = parseLRC("plain text\n[ar:Unknown]\n[00:61]bad\n[-1:00]bad\n[00:NaN]bad\n[00:01]Valid")
        check("L06 invalid timestamps and metadata are ignored", invalid.count == 1 && invalid[0].text == "Valid")
        check("L07 plain lyrics are not fabricated into timecodes", parseLRC("Words without a timestamp").isEmpty)
        check("L08 index before first line is absent", activeLyricIndex(in: basic, at: 1) == nil)
        check("L09 exact boundary picks new line", activeLyricIndex(in: basic, at: 2.5) == 1)
        check("L10 seek backwards repositions immediately", activeLyricIndex(in: basic, at: 3) == 2 && activeLyricIndex(in: basic, at: 1.5) == 0)
        check("L11 empty and invalid positions have no active line", activeLyricIndex(in: [], at: 1) == nil && activeLyricIndex(in: basic, at: .nan) == nil && activeLyricIndex(in: basic, at: -1) == nil)
        check("L12 after last line retains last sentence", activeLyricIndex(in: basic, at: 100) == 2)

        check("T01 clock advances using rate", playbackPosition(elapsed: 10, rate: 1, sampledAt: 100, now: 102, duration: 20) == 12)
        check("T02 pause freezes position", playbackPosition(elapsed: 10, rate: 0, sampledAt: 100, now: 102, duration: 20) == 10)
        check("T03 seek uses newest anchor", playbackPosition(elapsed: 3, rate: 1, sampledAt: 102, now: 102, duration: 20) == 3)
        check("T04 end clamps to duration", playbackPosition(elapsed: 19, rate: 2, sampledAt: 100, now: 102, duration: 20) == 20)
        check("T05 stale anchor is rejected", playbackPosition(elapsed: 10, rate: 1, sampledAt: 100, now: 105.001, duration: 20) == nil)
        check("T06 future and nonfinite anchors are rejected", playbackPosition(elapsed: 10, rate: 1, sampledAt: 101, now: 100, duration: 20) == nil && playbackPosition(elapsed: .nan, rate: 1, sampledAt: 100, now: 101, duration: 20) == nil)
        check("T07 invalid rates and duration are rejected", playbackPosition(elapsed: 10, rate: -1, sampledAt: 100, now: 101, duration: 20) == nil && playbackPosition(elapsed: 10, rate: 1, sampledAt: 100, now: 101, duration: 0) == nil && playbackPosition(elapsed: 10, rate: .infinity, sampledAt: 100, now: 101, duration: 20) == nil)

        check("S01 unique complete metadata matches", matchedSongID(for: metadata(), candidates: [candidate()]) == "123")
        check("S02 whitespace case and Unicode normalize", matchedSongID(for: metadata("  Café  SONG ", [" ARTIST "], " album "), candidates: [candidate("123", metadata("Cafe\u{301} song"))]) == "123")
        check("S03 version suffix is not discarded", matchedSongID(for: metadata(), candidates: [candidate("123", metadata("A Song (Live)"))]) == nil)
        check("S04 artist or album mismatch is rejected", matchedSongID(for: metadata(), candidates: [candidate("123", metadata("A Song", ["Other"])), candidate("124", metadata("A Song", ["Artist"], "Other Album"))]) == nil)
        check("S05 all artists required, set order may differ", matchedSongID(for: metadata("A Song", ["A", "B"]), candidates: [candidate("1", metadata("A Song", ["A"])), candidate("2", metadata("A Song", ["B", "A"]))]) == "2")
        check("S06 literal slash name is not split", matchedSongID(for: metadata("A Song", ["AC/DC"]), candidates: [candidate("1", metadata("A Song", ["AC", "DC"]))]) == nil)
        check("S07 exact complete flattened artist string can match", matchedSongID(for: metadata("A Song", ["A / B"]), candidates: [candidate("123", metadata("A Song", ["A", "B"]))]) == "123")
        check("S08 duration within one second is accepted", matchedSongID(for: metadata(), candidates: [candidate("123", metadata("A Song", ["Artist"], "Album", 181))]) == "123")
        check("S09 duration beyond tolerance rejected", matchedSongID(for: metadata(), candidates: [candidate("123", metadata("A Song", ["Artist"], "Album", 181.001))]) == nil)
        check("S10 ambiguous different IDs rejected", matchedSongID(for: metadata(), candidates: [candidate("123"), candidate("124")]) == nil)
        check("S11 duplicate same ID is one candidate", matchedSongID(for: metadata(), candidates: [candidate(), candidate()]) == "123")
        check("S12 missing metadata rejects", matchedSongID(for: metadata("", [], "", 0), candidates: [candidate("123", metadata("", [], "", 0))]) == nil)
        check("S13 invalid IDs never become a lyric request", ["", "0", "-1", "12x", "1e2", "https://example.com", "ABC-UUID"].allSatisfy { matchedSongID(for: metadata(), candidates: [candidate($0)]) == nil })
        check("S14 nonfinite duration rejects", matchedSongID(for: metadata(), candidates: [candidate("123", metadata("A Song", ["Artist"], "Album", .nan))]) == nil)

        var state = LyricState()
        check("R01 new session has no lyrics", state.trackKey == nil && state.lines.isEmpty)
        state.beginTrack("A")
        check("R02 current request is accepted", state.accept(basic, for: "A") && state.lines.count == 3)
        state.beginTrack("A")
        check("R03 same track refresh retains loaded lyrics", state.lines.count == 3)
        state.beginTrack("B")
        check("R04 track switch clears old lyrics immediately", state.trackKey == "B" && state.lines.isEmpty)
        check("R05 late old response cannot overwrite", !state.accept(basic, for: "A") && state.lines.isEmpty)
        _ = state.accept(multi, for: "B")
        state.beginTrack(nil)
        check("R06 unsupported or absent source clears and rejects", state.lines.isEmpty && !state.accept(multi, for: "B"))

        let silence = analyzeAudio(samples: Array(repeating: 0, count: 4096), sampleRate: 48000)
        check("A01 silence produces no rhythm", zero(silence))
        check("A02 empty input produces no rhythm", zero(analyzeAudio(samples: [], sampleRate: 48000)))
        check("A03 invalid sample rates produce no rhythm", [0.0, -1, Double.nan, Double.infinity].allSatisfy { zero(analyzeAudio(samples: tone(80), sampleRate: $0)) })
        check("A04 nonfinite samples cannot poison renderer", zero(analyzeAudio(samples: [0, .nan, 1], sampleRate: 48000)) && zero(analyzeAudio(samples: [.infinity], sampleRate: 48000)))
        let low = analyzeAudio(samples: tone(80), sampleRate: 48000)
        let mid = analyzeAudio(samples: tone(1000), sampleRate: 48000)
        let high = analyzeAudio(samples: tone(6000), sampleRate: 48000)
        check("A05 low tone drives low band", low.low > 0 && low.low > low.mid * 2 && low.low > low.high * 2)
        check("A06 mid tone drives mid band", mid.mid > 0 && mid.mid > mid.low * 2 && mid.mid > mid.high * 2)
        check("A07 high tone drives high band", high.high > 0 && high.high > high.low * 2 && high.high > high.mid * 2)
        check("A08 sine RMS follows real amplitude", near(mid.rms, 0.5 / sqrt(2), 0.01))
        let quieter = analyzeAudio(samples: tone(1000, 0.1), sampleRate: 48000)
        check("A09 quieter signal has lower energy", quieter.rms < mid.rms / 3 && quieter.mid < mid.mid)
        check("A10 all outputs are finite and normalized", [low, mid, high, analyzeAudio(samples: tone(1000, 4), sampleRate: 48000)].allSatisfy(bounded))
        let otherRate = analyzeAudio(samples: tone(1000, 0.5, 44100), sampleRate: 44100)
        check("A11 frequency uses actual sample rate", otherRate.mid > otherRate.low * 2 && otherRate.mid > otherRate.high * 2)
        check("A12 silence after loud input does not retain energy", zero(analyzeAudio(samples: Array(repeating: 0, count: 4096), sampleRate: 48000)))

        check("M01 system motion follows false only", desktopMotionEnabled(mode: "system", reduceMotion: false) && !desktopMotionEnabled(mode: "system", reduceMotion: true) && !desktopMotionEnabled(mode: "system", reduceMotion: nil))
        check("M02 always independent of system", desktopMotionEnabled(mode: "always", reduceMotion: true) && desktopMotionEnabled(mode: "always", reduceMotion: nil))
        check("M03 off and unknown never capture", ["off", "", "true", "ALWAYS", "invalid"].allSatisfy { !desktopMotionEnabled(mode: $0, reduceMotion: false) })

        let data = try! JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }
}
