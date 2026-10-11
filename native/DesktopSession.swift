import AppKit

final class DesktopSession {
    let model: DesktopModel
    private let lyrics = DesktopLyrics(cacheDirectory: LyricDiskCache.defaultDirectory)
    private let communityLyrics = CommunityLyrics(cacheDirectory: LyricDiskCache.defaultDirectory)
    private lazy var recovery = DesktopLyricRecovery(lyrics: lyrics, community: communityLyrics, cacheDirectory: LyricDiskCache.defaultDirectory)
    private var readableText: String?
    private var lyricsSource: String
    private var communityDocument: CommunityLyricDocument?
    private var lyricGeneration = UUID()
    private var state = LyricState()
    private var stream: DesktopMediaProcess?
    private var reader: DesktopMediaProcess?
    private var snapshot: DesktopSnapshot?
    private var heartbeat: Timer?
    private var clock: Timer?
    private var visible = true
    private var clockInterval = 0.0
    private var running = false
    private var checking = false
    private var revision = 0
    private var streamKey: String?
    private var lyricStatus = "等待网易云歌曲信息"
    var sourceChanged: ((DesktopSnapshot?) -> Void)?

    init(model: DesktopModel, lyricsSource: String = "netease") {
        self.model = model
        self.lyricsSource = lyricsSource == "community" ? "community" : "netease"
    }

    func setLyricsSource(_ source: String) {
        lyricsSource = source == "community" ? "community" : "netease"
        recovery.stop()
        resetLyrics()
        if let snapshot, running { loadLyrics(snapshot); render() }
    }

    private func resetLyrics() {
        lyricGeneration = UUID()
        communityDocument = nil
        readableText = nil
        state = LyricState()
        clearDisplayedLyrics()
    }

    private func clearDisplayedLyrics() {
        if !model.glassPage.isEmpty { model.glassPage = [] }
        model.lyricCue = nil; model.lyricPosition = nil
        model.lyric = ""; model.previousLine = ""; model.nextLine = ""
        model.timedLyric = nil; model.translation = ""; model.plainLyrics = nil
    }

    private func loadLyrics(_ value: DesktopSnapshot) {
        recovery.cancel()
        resetLyrics()
        state.beginTrack(value.key)
        lyricStatus = "正在获取歌词"
        let token = lyricGeneration
        recovery.load(key: value.key, metadata: value.metadata, preferredSource: lyricsSource) { [weak self] result in
            guard let self, self.running, self.lyricGeneration == token, self.state.accept(result.lines, for: value.key) else { return }
            self.communityDocument = result.community
            self.readableText = result.readableText
            self.lyricStatus = result.message
            self.render()
        }
    }

    func start() {
        guard !running else { return }
        running = true
        model.status = "正在读取网易云歌曲信息"
        let stream = DesktopMediaProcess()
        self.stream = stream
        DispatchQueue.global(qos: .utility).async { [weak self] in
            stream.run(stream: true) { data in
                let value = data.flatMap { DesktopSnapshot($0) }
                DispatchQueue.main.async { self?.receive(value) }
            }
        }
        heartbeat = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.verify() }
        scheduleClock()
        verify()
    }

    func setVisible(_ value: Bool) {
        guard visible != value else { return }
        visible = value
        scheduleClock()
    }

    private func scheduleClock() {
        guard running else { return }
        let interval = visible && snapshot?.playing == true ? 0.1 : 1.0
        guard clockInterval != interval else { return }
        clockInterval = interval
        clock?.invalidate()
        clock = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.render() }
    }

    func stop() {
        running = false
        revision += 1
        heartbeat?.invalidate(); heartbeat = nil
        clock?.invalidate(); clock = nil
        stream?.stop(); stream = nil
        reader?.stop(); reader = nil
        recovery.stop()
        clear()
    }

    private func receive(_ value: DesktopSnapshot?) {
        guard running else { return }
        // A same-track seek or pause is newer evidence too; discard any in-flight poll.
        revision += 1
        if streamKey != value?.key {
            streamKey = value?.key
            clear()
            verify()
        }
        guard let value else { clear(); return }
        if snapshot?.key == value.key { apply(value) }
        // A stream can combine independently emitted metadata; a new key requires two get snapshots.
    }

    private func verify() {
        guard running, !checking else { return }
        checking = true
        let token = revision
        let reader = DesktopMediaProcess()
        self.reader = reader
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var first: DesktopSnapshot?, second: DesktopSnapshot?
            reader.run(stream: false) { first = $0.flatMap { DesktopSnapshot($0) } }
            reader.run(stream: false) { second = $0.flatMap { DesktopSnapshot($0) } }
            let verified = first?.key == second?.key && first?.playing == second?.playing ? second : nil
            DispatchQueue.main.async {
                guard let self else { return }
                self.checking = false
                self.reader = nil
                guard self.running else { return }
                guard self.revision == token else { self.verify(); return }
                if let verified { self.apply(verified) } else { self.clear() }
            }
        }
    }

    private func apply(_ value: DesktopSnapshot) {
        let changed = state.trackKey != value.key
        snapshot = value
        scheduleClock()
        state.beginTrack(value.key)
        if model.title != value.metadata.title { model.title = value.metadata.title }
        let artists = value.metadata.artists.joined(separator: " / ")
        if model.artist != artists { model.artist = artists }
        if changed { loadLyrics(value) }
        sourceChanged?(value)
        render()
    }

    private func clear() {
        snapshot = nil
        scheduleClock()
        resetLyrics()
        recovery.cancel()
        sourceChanged?(nil)
        model.title = "Likeit"
        model.artist = "仅支持网易云音乐"
        model.progress = 0
        model.status = "暂无可靠网易云播放信息"
    }

    private func renderCommunity(_ lines: [CommunityLyricLine], at position: Double) {
        let index = lines.lastIndex { $0.start <= position }
        let current = index.map { lines[$0] }
        model.lyricCue = index.flatMap { index in snapshot.map { DesktopLyricCue(trackKey: $0.key, index: index, start: lines[index].start) } }
        let page: [DesktopGlassLyricLine] = index.flatMap { index in snapshot.map { snapshot in
            let start = index / 4 * 4
            return (start..<min(start + 4, lines.count)).map {
                DesktopGlassLyricLine(cue: DesktopLyricCue(trackKey: snapshot.key, index: $0, start: lines[$0].start), text: lines[$0].text)
            }
        } } ?? []
        if model.glassPage != page { model.glassPage = page }
        model.lyric = current?.text ?? ""
        model.translation = current?.translation ?? ""
        model.previousLine = index.flatMap { $0 > 0 ? lines[$0 - 1].text : nil } ?? ""
        model.nextLine = index.flatMap { $0 + 1 < lines.count ? lines[$0 + 1].text : nil } ?? (index == nil ? lines.first?.text ?? "" : "")
        model.timedLyric = current.map { communityHighlightedText($0, at: position) }
    }

    private func render() {
        guard let snapshot else { return }
        guard neteasePID() == snapshot.pid, ProcessInfo.processInfo.systemUptime - snapshot.sampledAt <= 5 else { clear(); return }
        model.plainLyrics = communityDocument?.plainText
        if communityDocument?.instrumental == true { model.lyric = "纯音乐" }
        guard let elapsed = snapshot.elapsed, let rate = snapshot.rate,
              let position = playbackPosition(elapsed: elapsed, rate: rate, sampledAt: snapshot.sampledAt, now: ProcessInfo.processInfo.systemUptime, duration: snapshot.metadata.duration) else {
            model.lyricCue = nil; model.lyricPosition = nil
            if !model.glassPage.isEmpty { model.glassPage = [] }
            model.lyric = communityDocument?.instrumental == true ? "纯音乐" : ""
            model.previousLine = ""; model.nextLine = ""; model.timedLyric = nil; model.translation = ""
            model.plainLyrics = readableText
            model.progress = 0
            model.status = lyricStatus + " · 播放进度不可用，静态显示"
            return
        }
        model.lyricPosition = position
        let progress = position / snapshot.metadata.duration
        if model.progress != progress { model.progress = progress }
        let status = lyricStatus + (snapshot.playing ? "" : " · 已暂停")
        if model.status != status { model.status = status }
        if let document = communityDocument {
            if document.plainText != nil || document.instrumental {
                model.lyricCue = nil
                if !model.glassPage.isEmpty { model.glassPage = [] }
                return
            }
            renderCommunity(document.lines, at: position)
            return
        }
        let lines = state.lines
        let index = activeLyricIndex(in: lines, at: position)
        model.lyricCue = index.map { DesktopLyricCue(trackKey: snapshot.key, index: $0, start: lines[$0].time) }
        let page: [DesktopGlassLyricLine] = index.map { index in
            let start = index / 4 * 4
            return (start..<min(start + 4, lines.count)).map {
                DesktopGlassLyricLine(cue: DesktopLyricCue(trackKey: snapshot.key, index: $0, start: lines[$0].time), text: lines[$0].text)
            }
        } ?? []
        if model.glassPage != page { model.glassPage = page }
        let current = index.map { lines[$0].text } ?? ""
        let previous = index.flatMap { $0 > 0 ? lines[$0 - 1].text : nil } ?? ""
        let next = index.flatMap { $0 + 1 < lines.count ? lines[$0 + 1].text : nil } ?? (index == nil ? lines.first?.text ?? "" : "")
        if model.lyric != current { model.lyric = current }
        if model.previousLine != previous { model.previousLine = previous }
        if model.nextLine != next { model.nextLine = next }
    }
}
