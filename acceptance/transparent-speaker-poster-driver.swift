// Appended in memory to the frozen motion fixture; private production methods stay intact.
extension RenderProbe {
    func resetForPoster() { resetLyrics() }
}

@main enum TransparentSpeakerPosterAcceptance {
    static func main() {
        let suite = "com.likeit.acceptance.glass-poster." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var results: [[String: Any]] = []
        func check(_ name: String, _ passed: Bool) { results.append(["name": name, "passed": passed]) }
        func snapshot(_ position: Double?, track: String = "track-a") -> DesktopSnapshot {
            var data: [String: Any] = [
                "bundleIdentifier": neteaseBundle, "processIdentifier": 77,
                "contentItemIdentifier": track, "title": "同名歌曲", "artist": "Artist", "album": "Album",
                "durationMicros": 120_000_000, "playing": false,
                "timestampEpochMicros": Date().timeIntervalSince1970 * 1_000_000,
            ]
            if let position { data["elapsedTimeMicros"] = position * 1_000_000; data["playbackRate"] = 0.0 }
            return DesktopSnapshot(data, expectedPID: 77)!
        }
        let probe = RenderProbe(DesktopModel(themeDefaults: defaults))
        let model = probe.model
        let texts = ["Keep Case 👩🏽‍💻", "同字异时", "同字异时", "  前后空格\t保留  ", "e\u{301} 和 é", "分组内\n原始换行", "第七行", "第八行", "最后一行 👨‍👩‍👧‍👦"]
        let times: [Double] = [1, 2.5, 4, 6.25, 8, 10.5, 13, 16.75, 20]
        let lines = zip(times, texts).map { LyricLine(time: $0.0, text: $0.1) }
        let community = zip(times, texts).map { start, text in
            CommunityLyricLine(start: start, end: start + 1, text: text, translation: "译文 " + text,
                               words: [CommunityLyricWord(start: start, end: start + 1, text: text, utf16Range: NSRange(location: 0, length: text.utf16.count))])
        }
        func expected(_ indices: [Int], key: String) -> [DesktopGlassLyricLine] {
            indices.map { DesktopGlassLyricLine(cue: DesktopLyricCue(trackKey: key, index: $0, start: times[$0]), text: texts[$0]) }
        }
        func load(_ value: DesktopSnapshot, communityDocument: CommunityLyricDocument? = nil) {
            probe.snapshot = value
            probe.state.beginTrack(value.key)
            probe.state.accept(lines, for: value.key)
            probe.communityDocument = communityDocument
            probe.readableText = texts.joined(separator: "\n")
        }
        func render(_ position: Double?, track: String = "track-a") {
            probe.snapshot = snapshot(position, track: track)
            probe.refresh()
        }
        let document = CommunityLyricDocument(source: .amll, lines: community, plainText: nil, instrumental: false)
        let pages = [(0, [0, 1, 2, 3]), (3, [0, 1, 2, 3]), (4, [4, 5, 6, 7]), (7, [4, 5, 6, 7]), (8, [8])]
        check("new model has no invented poster page", model.glassPage.isEmpty)
        let item = DesktopGlassLyricLine(cue: DesktopLyricCue(trackKey: "a", index: 0, start: 1), text: "Case")
        check("poster line equality includes both cue identity and unchanged text", item == DesktopGlassLyricLine(cue: item.cue, text: "Case") && item != DesktopGlassLyricLine(cue: item.cue, text: "CASE") && item != DesktopGlassLyricLine(cue: DesktopLyricCue(trackKey: "b", index: 0, start: 1), text: "Case"))

        load(snapshot(1.2))
        for (index, indices) in pages {
            render(times[index] + 0.2)
            check("LRC active index \(index) exposes fixed indices \(indices)", model.glassPage == expected(indices, key: probe.snapshot!.key))
        }
        render(1.2)
        let firstPage = expected([0, 1, 2, 3], key: probe.snapshot!.key)
        let firstCue = model.lyricCue
        render(1.3)
        check("100ms within one LRC cue keeps the entire page unchanged", model.glassPage == firstPage && model.lyricCue == firstCue && model.lyricPosition == 1.3)
        render(6.5)
        check("seeking inside one page changes current cue without shifting poster rows", model.glassPage == firstPage && model.lyricCue?.index == 3 && model.lyricCue?.start == 6.25)
        check("poster data preserves classic previous current next and progress fields", model.previousLine == texts[2] && model.lyric == texts[3] && model.nextLine == texts[4] && model.progress == 6.5 / 120)
        render(20.2)
        render(8.2)
        check("backward seek from the tail restores the middle fixed page", model.glassPage == expected([4, 5, 6, 7], key: probe.snapshot!.key))
        render(2.7)
        check("backward seek across another boundary restores the first page", model.glassPage == firstPage && model.lyricCue?.index == 1)
        load(snapshot(1.2, track: "track-b"))
        probe.refresh()
        check("another track with identical lyrics replaces every poster cue key", model.glassPage == expected([0, 1, 2, 3], key: probe.snapshot!.key) && model.glassPage != firstPage)

        load(snapshot(1.2), communityDocument: document)
        for (index, indices) in pages {
            render(times[index] + 0.2)
            check("community active index \(index) preserves real indices and times \(indices)", model.glassPage == expected(indices, key: probe.snapshot!.key))
        }
        render(1.2)
        let timedBefore = model.timedLyric
        render(1.3)
        let originalFirstPage = model.glassPage
        check("100ms word highlighting changes while the community page stays fixed", model.glassPage == firstPage && model.timedLyric != timedBefore && model.lyricCue?.index == 0)
        check("poster and community translation highlighting remain available together", model.lyric == texts[0] && model.translation == community[0].translation && model.timedLyric == communityHighlightedText(community[0], at: 1.3))
        render(2.7)
        let repeatedCue = model.lyricCue
        render(4.2)
        check("identical community words at different real times remain distinct rows", model.glassPage == firstPage && model.glassPage[1].text == model.glassPage[2].text && model.glassPage[1].cue != model.glassPage[2].cue && model.lyricCue != repeatedCue && model.lyricCue?.index == 2)
        render(8.2)
        check("poster preserves Unicode normalization emoji whitespace and embedded newlines", originalFirstPage.map { Array($0.text.utf8) } == texts.prefix(4).map { Array($0.utf8) } && model.glassPage.map { Array($0.text.utf8) } == texts[4...7].map { Array($0.utf8) })
        load(snapshot(1.2, track: "track-c"), communityDocument: document)
        probe.refresh()
        let trackPage = expected([0, 1, 2, 3], key: probe.snapshot!.key)
        check("community track changes replace page identity even for identical words", model.glassPage == trackPage && model.glassPage != firstPage)
        let savedCue = model.lyricCue, savedTimed = model.timedLyric, savedTranslation = model.translation
        model.motionEnabled = true
        for _ in 0..<10 {
            model.selectTheme("glass"); model.selectGlassScene("night")
            model.selectTheme("classic"); model.selectGlassScene("paper")
        }
        check("theme and scene changes preserve poster and existing lyric presentation", model.glassPage == trackPage && model.lyricCue == savedCue && model.lyricPosition == 1.2 && model.timedLyric == savedTimed && model.translation == savedTranslation && model.motionEnabled)

        // Seed real-shaped stale data so clearing branches are independently observable.
        model.glassPage = trackPage
        render(nil, track: "track-c")
        check("untrusted progress clears the poster but keeps static readable lyrics", model.glassPage.isEmpty && model.lyricCue == nil && model.lyricPosition == nil && model.plainLyrics == probe.readableText)
        load(snapshot(0.5))
        model.glassPage = trackPage
        probe.refresh()
        check("before the first LRC line has no visible or future poster page", model.glassPage.isEmpty && model.lyricCue == nil && model.lyricPosition == 0.5)
        load(snapshot(0.5), communityDocument: document)
        model.glassPage = trackPage
        probe.refresh()
        check("before the first community line clears its entire page", model.glassPage.isEmpty && model.lyricCue == nil)
        load(snapshot(1.2), communityDocument: document)
        model.glassPage = trackPage
        musicPID = nil
        probe.refresh()
        check("unknown music process clears all stale poster rows", model.glassPage.isEmpty && probe.snapshot == nil && model.lyricCue == nil)
        musicPID = 77
        load(snapshot(4), communityDocument: CommunityLyricDocument(source: .lrclib, lines: [], plainText: "静态\n全文", instrumental: false))
        model.glassPage = trackPage
        probe.refresh()
        check("plain text retains its scrolling content without a timed poster", model.glassPage.isEmpty && model.plainLyrics == "静态\n全文" && model.lyricPosition == 4)
        load(snapshot(4), communityDocument: CommunityLyricDocument(source: .lrclib, lines: [], plainText: nil, instrumental: true))
        model.glassPage = trackPage
        probe.refresh()
        check("instrumental content retains its label without invented poster rows", model.glassPage.isEmpty && model.lyric == "纯音乐" && model.lyricPosition == 4)
        load(snapshot(4))
        probe.state.accept([], for: probe.snapshot!.key)
        model.glassPage = trackPage
        probe.refresh()
        check("empty LRC clears a previously populated poster", model.glassPage.isEmpty && model.lyricCue == nil)
        load(snapshot(4), communityDocument: CommunityLyricDocument(source: .amll, lines: [], plainText: nil, instrumental: false))
        model.glassPage = trackPage
        probe.refresh()
        check("empty community lyrics clear a previously populated poster", model.glassPage.isEmpty && model.lyricCue == nil)
        model.glassPage = trackPage
        probe.clearDisplay()
        check("clearDisplayedLyrics clears all poster rows", model.glassPage.isEmpty)
        model.glassPage = trackPage
        probe.resetForPoster()
        check("resetLyrics clears poster rows along with acquired lyric state", model.glassPage.isEmpty && probe.communityDocument == nil && probe.state.lines.isEmpty)
        model.glassPage = trackPage
        probe.clearAll()
        check("source clearing removes the old poster page", model.glassPage.isEmpty && probe.snapshot == nil)
        load(snapshot(1.2))
        model.glassPage = trackPage
        probe.stop()
        check("session stop removes the poster before teardown completes", model.glassPage.isEmpty && !probe.running && probe.recovery.stops == 1)
        let reopened = DesktopModel(themeDefaults: defaults)
        check("reopening restores display choices without persisting old poster rows", reopened.glassPage.isEmpty && reopened.theme == .classic && reopened.glassScene == .paper)
        print(String(decoding: try! JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]), as: UTF8.self))
    }
}
