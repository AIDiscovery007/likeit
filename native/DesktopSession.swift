import AppKit

final class DesktopSession {
    let model: DesktopModel
    private let lyrics = DesktopLyrics()
    private var state = LyricState()
    private var stream: DesktopMediaProcess?
    private var reader: DesktopMediaProcess?
    private var snapshot: DesktopSnapshot?
    private var heartbeat: Timer?
    private var clock: Timer?
    private var running = false
    private var checking = false
    private var revision = 0
    private var streamKey: String?
    private var lyricStatus = "等待网易云歌曲信息"
    var sourceChanged: ((DesktopSnapshot?) -> Void)?

    init(model: DesktopModel) { self.model = model }

    func start() {
        guard !running else { return }
        running = true
        model.status = "正在读取网易云歌曲信息"
        let stream = DesktopMediaProcess()
        self.stream = stream
        DispatchQueue.global(qos: .utility).async { [weak self] in
            stream.run(stream: true) { data in
                let value = data.flatMap(DesktopSnapshot.init)
                DispatchQueue.main.async { self?.receive(value) }
            }
        }
        heartbeat = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.verify() }
        clock = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.render() }
        verify()
    }

    func stop() {
        running = false
        revision += 1
        heartbeat?.invalidate(); heartbeat = nil
        clock?.invalidate(); clock = nil
        stream?.stop(); stream = nil
        reader?.stop(); reader = nil
        lyrics.stop()
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
            reader.run(stream: false) { first = $0.flatMap(DesktopSnapshot.init) }
            reader.run(stream: false) { second = $0.flatMap(DesktopSnapshot.init) }
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
        state.beginTrack(value.key)
        model.title = value.metadata.title
        model.artist = value.metadata.artists.joined(separator: " / ")
        if changed {
            model.lyric = ""; model.previousLine = ""; model.nextLine = ""
            lyricStatus = "正在匹配歌词"
            lyrics.load(key: value.key, metadata: value.metadata) { [weak self] lines, message in
                guard let self, self.running, self.state.accept(lines, for: value.key) else { return }
                self.lyricStatus = message
                self.render()
            }
        }
        sourceChanged?(value)
        render()
    }

    private func clear() {
        snapshot = nil
        state.beginTrack(nil)
        lyrics.cancel()
        sourceChanged?(nil)
        model.title = "Likeit"
        model.artist = "仅支持网易云音乐"
        model.lyric = ""; model.previousLine = ""; model.nextLine = ""
        model.progress = 0
        model.status = "暂无可靠网易云播放信息"
    }

    private func render() {
        guard let snapshot else { return }
        guard neteasePID() == snapshot.pid, ProcessInfo.processInfo.systemUptime - snapshot.sampledAt <= 5 else { clear(); return }
        guard let elapsed = snapshot.elapsed, let rate = snapshot.rate,
              let position = playbackPosition(elapsed: elapsed, rate: rate, sampledAt: snapshot.sampledAt, now: ProcessInfo.processInfo.systemUptime, duration: snapshot.metadata.duration) else {
            model.lyric = ""; model.previousLine = ""; model.nextLine = ""
            model.status = lyricStatus + " · 播放进度不可用"
            return
        }
        model.progress = position / snapshot.metadata.duration
        model.status = lyricStatus + (snapshot.playing ? "" : " · 已暂停")
        let lines = state.lines
        if let index = activeLyricIndex(in: lines, at: position) {
            model.lyric = lines[index].text
            model.previousLine = index > 0 ? lines[index - 1].text : ""
            model.nextLine = index + 1 < lines.count ? lines[index + 1].text : ""
        } else {
            model.lyric = ""
            model.previousLine = ""
            model.nextLine = lines.first?.text ?? ""
        }
    }
}
