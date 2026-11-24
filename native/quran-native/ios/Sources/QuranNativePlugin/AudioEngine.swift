import AVFoundation
import MediaPlayer

/// Plays the wird natively: keeps playing with the screen locked / app in background,
/// shows controls on the lock screen and Control Center. Ayahs play from the phone when saved.
final class AudioEngine: NSObject {
    static let shared = AudioEngine()

    struct Item { let surah: Int; let ayah: Int; let rep: Int; let round: Int }

    /// Called with the playback state dictionary (main thread).
    var onState: (([String: Any]) -> Void)?

    private let player = AVPlayer()
    private var items: [Item] = []
    private var index = 0
    private var reciterId = "yassin"
    private var reciterName = ""
    private var title = ""
    private var speed: Float = 1
    private var failuresInARow = 0
    private var sleepTimer: Timer?
    private var sleepAt: Date?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var remoteReady = false
    private let prefetchQueue = DispatchQueue(label: "quran.audio.prefetch", qos: .utility)
    private var prefetchToken = 0

    var isActive: Bool { !items.isEmpty }
    var isPlaying: Bool { player.timeControlStatus != .paused || (player.rate > 0) }

    // MARK: control

    func play(reciter: String, list: [(Int, Int)], ayahRepeat: Int, rangeRepeat: Int, speed: Float, title: String) {
        let r = Reciters.byId(reciter) ?? Reciters.all[0]
        reciterId = r.id
        reciterName = r.name
        self.title = title
        self.speed = max(0.5, min(2, speed))
        failuresInARow = 0
        var built: [Item] = []
        let per = max(1, min(20, ayahRepeat)), rounds = max(1, min(50, rangeRepeat))
        for round in 1...rounds { for (s, a) in list { for k in 1...per { built.append(Item(surah: s, ayah: a, rep: k, round: round)) } } }
        guard !built.isEmpty else { return }
        items = built
        index = 0
        activateSession()
        setupRemoteCommands()
        playCurrent()

        // save the wird's ayahs on the phone in the background
        prefetchToken += 1
        let token = prefetchToken
        let unique = list.reduce(into: [(Int, Int)]()) { acc, p in if !acc.contains(where: { $0 == p }) { acc.append(p) } }
        let rid = r.id
        prefetchQueue.async { [weak self] in
            for (s, a) in unique {
                guard let self = self, token == self.prefetchToken else { return }
                OfflineStore.shared.ensureAudio(rid, s, a)
            }
        }
    }

    func stop(emitEvent: String? = "stopped") {
        cancelSleep()
        prefetchToken += 1
        player.pause()
        player.replaceCurrentItem(with: nil)
        items = []
        index = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        emit(emitEvent)
    }

    func togglePause() {
        guard isActive else { return }
        if player.rate > 0 { player.pause() } else { player.playImmediately(atRate: speed) }
        updateNowPlaying()
        emit(nil)
    }

    func setSpeed(_ s: Float) {
        speed = max(0.5, min(2, s))
        if player.rate > 0 { player.rate = speed }
        updateNowPlaying()
    }

    func setSleepTimer(minutes: Int) {
        cancelSleep()
        if minutes > 0 {
            sleepAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
            sleepTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.sleepAt = nil
                self.player.pause()
                self.updateNowPlaying()
                self.emit("sleep")
            }
        }
        emit(nil)
    }

    private func cancelSleep() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepAt = nil
    }

    // MARK: playback

    private func activateSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .spokenAudio, options: [])
        try? s.setActive(true)
    }

    private func playCurrent() {
        guard index < items.count else { finishAll(); return }
        let it = items[index]
        let url = OfflineStore.shared.audioURL(reciterId, it.surah, it.ayah)
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain
        observe(item)
        player.replaceCurrentItem(with: item)
        player.playImmediately(atRate: speed)
        updateNowPlaying()
        emit(nil)
    }

    private func observe(_ item: AVPlayerItem) {
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        if let o = failObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.failuresInARow = 0
            self.index += 1
            self.playCurrent()
        }
        failObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.skipAfterError()
        }
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            if it.status == .failed { DispatchQueue.main.async { self?.skipAfterError() } }
            if it.status == .readyToPlay { DispatchQueue.main.async { self?.failuresInARow = 0 } }
        }
    }

    /// Ayah not available (e.g. offline and not saved): skip it; give up after 3 in a row.
    private func skipAfterError() {
        failuresInARow += 1
        if failuresInARow >= 3 || index + 1 >= items.count {
            stop(emitEvent: "error")
        } else {
            index += 1
            playCurrent()
        }
    }

    private func finishAll() {
        stop(emitEvent: "ended")
    }

    // MARK: lock screen / Control Center

    private func setupRemoteCommands() {
        guard !remoteReady else { return }
        remoteReady = true
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            guard let self = self, self.isActive else { return .noActionableNowPlayingItem }
            self.player.playImmediately(atRate: self.speed); self.updateNowPlaying(); self.emit(nil); return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.player.pause(); self.updateNowPlaying(); self.emit(nil); return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePause(); return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self, self.index + 1 < self.items.count else { return .noSuchContent }
            self.index += 1; self.playCurrent(); return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self, self.isActive else { return .noSuchContent }
            self.index = max(0, self.index - 1); self.playCurrent(); return .success
        }
    }

    private func updateNowPlaying() {
        guard index < items.count else { return }
        let it = items[index]
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: "\(title) — الآية \(it.ayah)",
            MPMediaItemPropertyArtist: reciterName,
            MPMediaItemPropertyAlbumTitle: "أسهل نظام لحفظ القرآن",
            MPNowPlayingInfoPropertyPlaybackRate: player.rate > 0 ? speed : 0,
        ]
        if let d = player.currentItem?.duration, d.isNumeric { info[MPMediaItemPropertyPlaybackDuration] = d.seconds }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime().seconds
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: state for the page

    func state(event: String? = nil) -> [String: Any] {
        var o: [String: Any] = [
            "active": isActive,
            "playing": isActive && player.rate > 0,
            "reciter": reciterId,
            "sleepLeftMin": sleepAt.map { max(0, Int(ceil($0.timeIntervalSinceNow / 60))) } ?? 0,
        ]
        if index < items.count {
            let it = items[index]
            o["surah"] = it.surah; o["ayah"] = it.ayah; o["rep"] = it.rep; o["round"] = it.round
        }
        if let e = event { o["event"] = e }
        return o
    }

    private func emit(_ event: String?) {
        let s = state(event: event)
        DispatchQueue.main.async { self.onState?(s) }
    }
}
