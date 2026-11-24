import Foundation
import UserNotifications

/// Saved mushaf pages and ayah recitations on the phone, and bulk downloads that continue
/// in the background (iOS background URLSession) with a notification when they finish.
final class OfflineStore: NSObject, URLSessionDownloadDelegate {
    static let shared = OfflineStore()

    /// Called with a JSON-able progress dictionary (main thread).
    var onProgress: (([String: Any]) -> Void)?
    /// Completion handler iOS gives the app when it wakes it up for background download events.
    var backgroundCompletion: (() -> Void)?

    let root: URL
    private let fm = FileManager.default
    private let pageURLTemplate = "https://cdn.quran.ws/svg/pages/v1.1.1/%@/%@.svg"
    private lazy var plainSession: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.httpAdditionalHeaders = ["User-Agent": "AshalNidamHifzQuran-iOS"]
        return URLSession(configuration: c)
    }()
    private var bgSession: URLSession!

    // current bulk job
    private let jobKey = "offline_job"
    private var lastProgressAt = Date.distantPast

    override init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appendingPathComponent("offline", isDirectory: true)
        super.init()
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        var noBackup = URLResourceValues()
        noBackup.isExcludedFromBackup = true
        var r = root
        try? r.setResourceValues(noBackup)
        let cfg = URLSessionConfiguration.background(withIdentifier: "com.ashalnidamhifz.quran.offline")
        cfg.httpMaximumConnectionsPerHost = 4
        cfg.sessionSendsLaunchEvents = true
        cfg.isDiscretionary = false
        bgSession = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }

    // MARK: files

    func audioFile(_ reciterId: String, _ code: String) -> URL {
        root.appendingPathComponent("audio/\(reciterId)/\(code).mp3")
    }
    func pageFile(_ edition: String, _ num: String) -> URL {
        root.appendingPathComponent("pages/\(edition)/\(num).svg")
    }

    /// Saved file if present, else the online URL.
    func audioURL(_ reciterId: String, _ s: Int, _ a: Int) -> URL {
        let r = Reciters.byId(reciterId) ?? Reciters.all[0]
        let c = QuranMeta.code(s, a)
        let f = audioFile(r.id, c)
        return fm.fileExists(atPath: f.path) ? f : r.url(c)
    }

    /// Downloads one ayah if missing (blocking; call off the main thread).
    @discardableResult
    func ensureAudio(_ reciterId: String, _ s: Int, _ a: Int) -> Bool {
        guard let r = Reciters.byId(reciterId) else { return false }
        let c = QuranMeta.code(s, a)
        return fetchBlocking(r.url(c), to: audioFile(r.id, c))
    }

    /// Saves one mushaf page in the background; completion(true) when the file is on the phone.
    func cachePage(_ edition: String, _ num: String, completion: @escaping (Bool) -> Void) {
        let dest = pageFile(edition, num)
        if fm.fileExists(atPath: dest.path) { completion(true); return }
        guard let url = URL(string: String(format: pageURLTemplate, edition, num)) else { completion(false); return }
        DispatchQueue.global(qos: .utility).async {
            completion(self.fetchBlocking(url, to: dest))
        }
    }

    func cachedPages(_ edition: String) -> [String] {
        let dir = root.appendingPathComponent("pages/\(edition)")
        return ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasSuffix(".svg") }
            .map { String($0.dropLast(4)) }
    }

    private func fetchBlocking(_ url: URL, to dest: URL) -> Bool {
        if fm.fileExists(atPath: dest.path) { return true }
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        plainSession.dataTask(with: url) { data, resp, _ in
            if let data = data, !data.isEmpty, (resp as? HTTPURLResponse)?.statusCode == 200 {
                ok = self.store(data, at: dest)
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 40)
        return ok
    }

    private func store(_ data: Data, at dest: URL) -> Bool {
        do {
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: dest, options: .atomic)
            return true
        } catch { return false }
    }

    // MARK: bulk downloads (background session)

    private var job: [String: Any] {
        get { UserDefaults.standard.dictionary(forKey: jobKey) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: jobKey) }
    }

    var running: Bool { (job["running"] as? Bool) == true }

    /// kind "audio": key = reciter id, surahs from...to. kind "pages": key = riwayah.
    func startDownload(kind: String, key: String, from: Int, to: Int) -> Bool {
        if running { return false }
        var items: [(URL, URL)] = []
        if kind == "pages" {
            let edition = key == "warsh" ? "warsh-kfqc" : "hafs-kfqc"
            for p in 1...604 {
                let num = String(format: "%03d", p)
                if let u = URL(string: String(format: pageURLTemplate, edition, num)) { items.append((u, pageFile(edition, num))) }
            }
        } else {
            guard let r = Reciters.byId(key) else { return false }
            let a = max(1, min(114, from)), b = max(1, min(114, to))
            for s in a...b {
                for ay in 1...QuranMeta.ayahCounts[s] {
                    let c = QuranMeta.code(s, ay)
                    items.append((r.url(c), audioFile(r.id, c)))
                }
            }
        }
        let todo = items.filter { !fm.fileExists(atPath: $0.1.path) }
        job = ["running": !todo.isEmpty, "kind": kind, "key": key, "total": items.count,
               "done": items.count - todo.count, "failed": 0, "cancelled": false]
        if todo.isEmpty { finish(); return true }
        for (src, dest) in todo {
            let t = bgSession.downloadTask(with: src)
            t.taskDescription = dest.path
            t.resume()
        }
        report(force: true)
        return true
    }

    func cancelDownload() {
        var j = job
        j["cancelled"] = true
        job = j
        bgSession.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
            DispatchQueue.main.async { self.finish() }
        }
    }

    private func finish() {
        var j = job
        let wasRunning = (j["running"] as? Bool) == true
        j["running"] = false
        job = j
        report(force: true, finished: true)
        if wasRunning { notifyDone(j) }
    }

    private func report(force: Bool = false, finished: Bool = false) {
        let now = Date()
        if !force && now.timeIntervalSince(lastProgressAt) < 0.4 { return }
        lastProgressAt = now
        var p = job
        p["finished"] = finished || !running
        p.removeValue(forKey: "running")
        DispatchQueue.main.async { self.onProgress?(p) }
    }

    private func notifyDone(_ j: [String: Any]) {
        let kind = j["kind"] as? String ?? "audio"
        let key = j["key"] as? String ?? ""
        let done = j["done"] as? Int ?? 0, total = j["total"] as? Int ?? 0, failed = j["failed"] as? Int ?? 0
        let content = UNMutableNotificationContent()
        if (j["cancelled"] as? Bool) == true {
            content.title = "تم إيقاف التحميل"
            content.body = "تم حفظ \(done) من \(total). اضغط «تحميل» في الإعدادات للمتابعة."
        } else if failed > 0 {
            content.title = "اكتمل التحميل جزئياً"
            content.body = "تعذّر تحميل \(failed) ملف. أعد المحاولة عند توفر اتصال أفضل."
        } else {
            content.title = "اكتمل التحميل ✓"
            content.body = kind == "pages"
                ? "صفحات المصحف متوفرة الآن بدون إنترنت (رواية \(key == "warsh" ? "ورش" : "حفص"))."
                : "التلاوة متوفرة الآن بدون إنترنت (\(Reciters.byId(key)?.name ?? ""))."
        }
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "offline-done", content: content, trigger: nil))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let path = downloadTask.taskDescription else { return }
        let dest = URL(fileURLWithPath: path)
        let okStatus = (downloadTask.response as? HTTPURLResponse)?.statusCode == 200
        if okStatus {
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: dest)
            try? fm.moveItem(at: location, to: dest)
        }
        var j = job
        if okStatus && fm.fileExists(atPath: dest.path) { j["done"] = (j["done"] as? Int ?? 0) + 1 }
        else { j["failed"] = (j["failed"] as? Int ?? 0) + 1 }
        job = j
        report()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let e = error as NSError?, e.code != NSURLErrorCancelled {
            var j = job
            j["failed"] = (j["failed"] as? Int ?? 0) + 1
            job = j
        }
        session.getAllTasks { tasks in
            if tasks.filter({ $0.state == .running || $0.state == .suspended }).isEmpty && self.running {
                DispatchQueue.main.async { self.finish() }
            }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletion?()
            self.backgroundCompletion = nil
        }
    }

    // MARK: status / clear

    func status() -> [String: Any] {
        func count(_ dir: String) -> Int {
            ((try? fm.contentsOfDirectory(atPath: root.appendingPathComponent(dir).path)) ?? []).count
        }
        var audio: [String: Int] = [:]
        for r in Reciters.all { audio[r.id] = count("audio/\(r.id)") }
        var bytes: Int64 = 0
        if let e = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let u as URL in e { bytes += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
        var progress: Any = NSNull()
        if !job.isEmpty { var p = job; p["finished"] = !running; p.removeValue(forKey: "running"); progress = p }
        return ["audio": audio, "pagesWarsh": count("pages/warsh-kfqc"), "pagesHafs": count("pages/hafs-kfqc"),
                "totalAyahs": 6236, "totalPages": 604, "bytes": bytes, "running": running, "progress": progress]
    }

    func clear(_ what: String) -> Bool {
        if running { return false }
        switch what {
        case "audio": try? fm.removeItem(at: root.appendingPathComponent("audio"))
        case "pages": try? fm.removeItem(at: root.appendingPathComponent("pages"))
        default:
            try? fm.removeItem(at: root)
            try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        }
        job = [:]
        return true
    }
}
