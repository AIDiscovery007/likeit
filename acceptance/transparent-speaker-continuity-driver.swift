// Layout is a storage-only record; all continuity and transition decisions come from receive.
private struct GlassPosterLayout {
    let lines: [DesktopGlassLyricLine]
    init(page: [DesktopGlassLyricLine] = [], size: CGSize = .zero) { lines = page }
}
private final class ContinuityProbe {
    // PRODUCTION_INPUT
    // PRODUCTION_ARRIVAL
    private var previous: Input?
    private var arrival: Arrival?
    private var layout = GlassPosterLayout()
    private let size = CGSize(width: 1280, height: 800)
    var page: [DesktopGlassLyricLine] { layout.lines }
    var latestCue: DesktopLyricCue? { previous?.cue }
    var enteringCue: DesktopLyricCue? { arrival?.cue }
    var hasDeparture: Bool { arrival?.departing != nil }
    func submit(page: [DesktopGlassLyricLine], cue: DesktopLyricCue, sample: DesktopLyricSample?, enabled: Bool = true) {
        receive(Input(page: page, cue: cue, sample: sample, enabled: enabled))
    }
    func seedOngoingTransition() { arrival = Arrival(cue: previous!.cue!, departing: layout) }
    // PRODUCTION_RECEIVE
}

@main enum TransparentSpeakerContinuityAcceptance {
    static func main() {
        var results: [[String: Any]] = []
        func check(_ name: String, _ passed: Bool) { results.append(["name": name, "passed": passed]) }
        func sample(_ position: Double, _ time: Double, _ rate: Double = 1) -> DesktopLyricSample {
            DesktopLyricSample(position: position, sampledAt: time, rate: rate)
        }
        func cue(_ index: Int, track: String = "track-a") -> DesktopLyricCue {
            DesktopLyricCue(trackKey: track, index: index, start: Double(index))
        }
        func page(_ value: DesktopLyricCue) -> [DesktopGlassLyricLine] {
            (value.index < 4 ? [0, 1, 2, 3] : [4, 5, 6, 7]).map {
                DesktopGlassLyricLine(cue: cue($0, track: value.trackKey), text: "真实行 \($0)")
            }
        }
        func feed(_ old: DesktopLyricSample?, _ next: DesktopLyricSample?, oldCue: DesktopLyricCue = DesktopLyricCue(trackKey: "track-a", index: 3, start: 3), newCue: DesktopLyricCue = DesktopLyricCue(trackKey: "track-a", index: 4, start: 4), enabled: Bool = true, delay: Double = 0) -> ContinuityProbe {
            let probe = ContinuityProbe()
            probe.submit(page: page(oldCue), cue: oldCue, sample: old)
            probe.seedOngoingTransition()
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            probe.submit(page: page(newCue), cue: newCue, sample: next, enabled: enabled)
            return probe
        }
        func cancelled(_ probe: ContinuityProbe, _ current: DesktopLyricCue = DesktopLyricCue(trackKey: "track-a", index: 4, start: 4)) -> Bool {
            probe.enteringCue == nil && !probe.hasDeparture && probe.latestCue == current && probe.page == page(current)
        }
        check("receive: adjacent cross-page seek with 150ms residual shows latest page immediately", cancelled(feed(sample(3.9, 100), sample(4.15, 100.1))))
        let delayed = feed(sample(3.9, 100), sample(4, 100.1), delay: 0.65)
        check("receive: a late View observation does not reject continuous source samples", delayed.enteringCue == cue(4) && delayed.hasDeparture && delayed.page == page(cue(4)))
        for rate in [0.5, 2.0, 4.0] {
            let probe = feed(sample(3.99, 100, rate), sample(3.99 + rate * 0.1, 100.1, rate))
            check("receive: normal \(rate)x playback enters the adjacent cue", probe.enteringCue == cue(4) && probe.hasDeparture)
        }
        check("receive: a rate change cancels an existing transition", cancelled(feed(sample(3.9, 100), sample(4, 100.1, 2))))
        let missing = [(nil, sample(4, 100.1)), (sample(3.9, 100), nil)] as [(DesktopLyricSample?, DesktopLyricSample?)]
        check("receive: either missing source sample cancels old entrance and departure", missing.map { cancelled(feed($0.0, $0.1)) }.allSatisfy { $0 })
        for (name, time) in [("backward", 99.9), ("zero", 100.0), ("over 500ms", 100.501)] {
            check("receive: \(name) sample interval cannot animate", cancelled(feed(sample(3.9, 100), sample(4, time))))
        }
        let nonpositive = [0.0, -1.0].map { rate in
            cancelled(feed(sample(3.9, 100, rate), sample(3.9 + rate * 0.1, 100.1, rate), newCue: cue(3)), cue(3))
        }
        check("receive: paused and negative rates cancel even a same-cue transition", nonpositive.allSatisfy { $0 })
        check("receive: backward seek replaces the page and drops all transitions", cancelled(feed(sample(4.1, 100), sample(3.9, 100.1), oldCue: cue(4), newCue: cue(3)), cue(3)))
        check("receive: a large forward jump never animates through skipped time", cancelled(feed(sample(3.9, 100), sample(4.9, 100.1))))
        check("receive: track changes cancel even when sample deltas look continuous", cancelled(feed(sample(3.9, 100), sample(4, 100.1), newCue: cue(4, track: "track-b")), cue(4, track: "track-b")))
        check("receive: gate off cancels entrance and old page immediately", cancelled(feed(sample(3.9, 100), sample(4, 100.1), enabled: false)))
        check("receive: a 150ms same-cue seek cancels the in-flight entrance", cancelled(feed(sample(3.4, 100), sample(3.65, 100.1), newCue: cue(3)), cue(3)))

        let suite = "com.likeit.acceptance.lyric-sample." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let render = RenderProbe(DesktopModel(themeDefaults: defaults))
        let model = render.model
        let initiallyEmpty = model.lyricSample == nil
        func source(_ position: Double?, rate: Double = 1) -> DesktopSnapshot {
            var data: [String: Any] = [
                "bundleIdentifier": neteaseBundle, "processIdentifier": 77,
                "contentItemIdentifier": "source-track", "title": "真实来源", "artist": "Artist", "album": "Album",
                "durationMicros": 120_000_000, "playing": rate > 0,
                "timestampEpochMicros": Date().timeIntervalSince1970 * 1_000_000,
            ]
            if let position { data["elapsedTimeMicros"] = position * 1_000_000; data["playbackRate"] = rate }
            return DesktopSnapshot(data, expectedPID: 77)!
        }
        func load(_ snapshot: DesktopSnapshot, document: CommunityLyricDocument? = nil) {
            render.snapshot = snapshot
            render.state.beginTrack(snapshot.key)
            render.state.accept([LyricLine(time: 1, text: "真实歌词")], for: snapshot.key)
            render.communityDocument = document
        }
        let moving = source(2, rate: 2)
        load(moving)
        let before = ProcessInfo.processInfo.systemUptime
        render.refresh()
        let after = ProcessInfo.processInfo.systemUptime
        let generated = model.lyricSample
        let expectedPosition = generated.flatMap {
            playbackPosition(elapsed: moving.elapsed!, rate: moving.rate!, sampledAt: moving.sampledAt, now: $0.sampledAt, duration: moving.metadata.duration)
        }
        check("session: rate 2 sample and displayed position use the same source timestamp", initiallyEmpty && generated?.rate == 2 && generated?.position == model.lyricPosition && generated?.position == expectedPosition && generated.map { (before...after).contains($0.sampledAt) } == true)
        load(source(2.5, rate: 0))
        render.refresh()
        check("session: paused rate zero is preserved with its trusted position", model.lyricSample?.rate == 0 && model.lyricSample?.position == 2.5 && model.lyricPosition == 2.5)
        let documents: [CommunityLyricDocument?] = [nil,
            CommunityLyricDocument(source: .lrclib, lines: [], plainText: "静态全文", instrumental: false),
            CommunityLyricDocument(source: .lrclib, lines: [], plainText: nil, instrumental: true)]
        let staticSamples = documents.map { document -> Bool in
            load(source(document == nil ? 0.5 : 2, rate: 0), document: document)
            render.refresh()
            return model.lyricSample != nil && model.glassPage.isEmpty && model.lyricCue == nil
        }
        check("session: before-first plain and instrumental states keep a sample without inventing a page", staticSamples.allSatisfy { $0 })
        load(source(nil))
        model.lyricSample = sample(2, 100)
        render.refresh()
        let noPosition = model.lyricSample == nil && model.lyricPosition == nil
        load(source(2))
        model.lyricSample = sample(2, 100)
        musicPID = nil
        render.refresh()
        musicPID = 77
        check("session: unknown progress or lost source clears the sample", noPosition && model.lyricSample == nil && model.lyricPosition == nil)
        model.lyricSample = sample(2, 100)
        render.clearDisplay()
        let displayCleared = model.lyricSample == nil
        model.lyricSample = sample(2, 100)
        render.clearAll()
        let sourceCleared = model.lyricSample == nil
        model.lyricSample = sample(2, 100)
        render.stop()
        check("session: display clear source clear and stop remove the old sample", displayCleared && sourceCleared && model.lyricSample == nil && !render.running)
        print(String(decoding: try! JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]), as: UTF8.self))
    }
}
