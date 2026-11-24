import Foundation
import UIKit
import Capacitor
import WebKit

/// Bridge between the shared web app (www/index.html, same as Android) and iOS-native features.
/// The page talks to it through www/ios-bridge.js, which exposes the same `AndroidBridge` API.
@objc(QuranNativePlugin)
public class QuranNativePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "QuranNativePlugin"
    public let jsName = "QuranNative"
    public let pluginMethods: [CAPPluginMethod] = [
        "appInfo", "setKeepScreenOn", "setDarkMode", "requestNotifications", "testNotification",
        "scheduleReminders", "setWird", "setWirdStatus", "consumePendingDone", "getPendingShortcut",
        "audioPlay", "audioStop", "audioToggle", "audioSetSpeed", "audioSleep", "audioState",
        "speechAvailable", "speechStart", "speechStop",
        "offlineStatus", "tafsirGet", "offlineDownload", "offlineCancel", "offlineClear", "cachePage", "cachedPages",
        "saveBackup", "autoBackup", "autoBackupInfo", "share", "openURL", "debugLog",
    ].map { CAPPluginMethod(name: $0, returnType: CAPPluginReturnPromise) }

    private var observers: [NSObjectProtocol] = []

    override public func load() {
        // Automated simulator tests only: start with a given saved state (set via `defaults write`)
        if let testState = UserDefaults.standard.string(forKey: "ui_test_state"), !testState.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: [testState]),
           let quoted = String(data: data, encoding: .utf8) {
            let js = "try{var s=\(quoted)[0];if(!localStorage.getItem('ashal_hifz_quran_v2'))localStorage.setItem('ashal_hifz_quran_v2',s);}catch(e){}"
            bridge?.webView?.configuration.userContentController.addUserScript(
                WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        Reminders.shared.setup()
        AudioEngine.shared.onState = { [weak self] s in self?.notifyListeners("audio", data: s) }
        OfflineStore.shared.onProgress = { [weak self] p in self?.notifyListeners("offline", data: p) }
        SpeechEngine.shared.onEvent = { [weak self] ev, payload in
            var d = payload; d["type"] = ev
            self?.notifyListeners("speech", data: d)
        }
        let nc = NotificationCenter.default
        for name in [UIApplication.didBecomeActiveNotification, Notification.Name("QuranPendingDone"), Notification.Name("QuranShortcut")] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.notifyListeners("resume", data: [:])
            })
        }
    }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    // MARK: app

    @objc func appInfo(_ call: CAPPluginCall) {
        let info = Bundle.main.infoDictionary ?? [:]
        call.resolve([
            "version": info["CFBundleShortVersionString"] as? String ?? "",
            "build": info["CFBundleVersion"] as? String ?? "",
            "offlineRoot": OfflineStore.shared.root.path,
        ])
    }

    @objc func setKeepScreenOn(_ call: CAPPluginCall) {
        let on = call.getBool("on") ?? false
        DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = on }
        call.resolve()
    }

    @objc func setDarkMode(_ call: CAPPluginCall) {
        let dark = call.getBool("dark") ?? false
        DispatchQueue.main.async {
            let bg = dark ? UIColor(red: 0.043, green: 0.082, blue: 0.071, alpha: 1) : UIColor(red: 0.980, green: 0.973, blue: 0.953, alpha: 1)
            self.bridge?.viewController?.overrideUserInterfaceStyle = dark ? .dark : .light
            self.bridge?.viewController?.view.backgroundColor = bg
            self.bridge?.webView?.backgroundColor = bg
            self.bridge?.webView?.scrollView.backgroundColor = bg
            self.bridge?.viewController?.setNeedsStatusBarAppearanceUpdate()
        }
        call.resolve()
    }

    @objc func openURL(_ call: CAPPluginCall) {
        guard let s = call.getString("url"), let u = URL(string: s), ["https", "http"].contains(u.scheme ?? "") else {
            call.reject("bad url"); return
        }
        DispatchQueue.main.async { UIApplication.shared.open(u) }
        call.resolve()
    }

    @objc func debugLog(_ call: CAPPluginCall) {
        NSLog("QuranDBG js: %@", call.getString("msg") ?? "")
        call.resolve()
    }

    @objc func getPendingShortcut(_ call: CAPPluginCall) {
        let d = UserDefaults.standard
        let v = d.string(forKey: "pending_shortcut") ?? ""
        NSLog("QuranDBG getPendingShortcut -> '%@'", v)
        if !v.isEmpty { d.removeObject(forKey: "pending_shortcut") }
        call.resolve(["value": v])
    }

    // MARK: reminders

    @objc func requestNotifications(_ call: CAPPluginCall) {
        Reminders.shared.requestPermission { ok in call.resolve(["granted": ok]) }
    }

    @objc func testNotification(_ call: CAPPluginCall) {
        Reminders.shared.requestPermission { _ in
            Reminders.shared.showNow(title: "تذكير ورد القرآن اليومي")
            call.resolve()
        }
    }

    @objc func scheduleReminders(_ call: CAPPluginCall) {
        Reminders.shared.setTimes(call.getString("time1") ?? "05:30", call.getBool("enabled2") ?? false, call.getString("time2") ?? "21:00")
        call.resolve()
    }

    @objc func setWird(_ call: CAPPluginCall) {
        Reminders.shared.setWird(surah: call.getString("surah") ?? "", detail: call.getString("detail") ?? "")
        call.resolve()
    }

    @objc func setWirdStatus(_ call: CAPPluginCall) {
        Reminders.shared.setStatus(key: call.getString("key") ?? "", doneDate: call.getString("doneDate") ?? "")
        call.resolve()
    }

    @objc func consumePendingDone(_ call: CAPPluginCall) {
        call.resolve(["value": Reminders.shared.consumePendingDone()])
    }

    // MARK: audio

    @objc func audioPlay(_ call: CAPPluginCall) {
        let raw = call.getArray("items", [Int].self) ?? []
        let list = raw.compactMap { $0.count >= 2 ? ($0[0], $0[1]) : nil }
        let reciter = call.getString("reciter") ?? "yassin"
        let ayahRepeat = call.getInt("ayahRepeat") ?? 1
        let rangeRepeat = call.getInt("rangeRepeat") ?? 1
        let speed = Float(call.getDouble("speed") ?? 1)
        let title = call.getString("title") ?? ""
        DispatchQueue.main.async {
            AudioEngine.shared.play(reciter: reciter, list: list, ayahRepeat: ayahRepeat, rangeRepeat: rangeRepeat, speed: speed, title: title)
            call.resolve()
        }
    }

    @objc func audioStop(_ call: CAPPluginCall) { DispatchQueue.main.async { AudioEngine.shared.stop(); call.resolve() } }
    @objc func audioToggle(_ call: CAPPluginCall) { DispatchQueue.main.async { AudioEngine.shared.togglePause(); call.resolve() } }
    @objc func audioSetSpeed(_ call: CAPPluginCall) {
        let s = Float(call.getDouble("speed") ?? 1)
        DispatchQueue.main.async { AudioEngine.shared.setSpeed(s); call.resolve() }
    }
    @objc func audioSleep(_ call: CAPPluginCall) {
        let m = call.getInt("minutes") ?? 0
        DispatchQueue.main.async { AudioEngine.shared.setSleepTimer(minutes: m); call.resolve() }
    }
    @objc func audioState(_ call: CAPPluginCall) { DispatchQueue.main.async { call.resolve(AudioEngine.shared.state()) } }

    // MARK: speech

    @objc func speechAvailable(_ call: CAPPluginCall) { call.resolve(["value": SpeechEngine.shared.available]) }
    @objc func speechStart(_ call: CAPPluginCall) {
        let lang = call.getString("lang") ?? "ar-SA"
        DispatchQueue.main.async { SpeechEngine.shared.start(lang: lang); call.resolve() }
    }
    @objc func speechStop(_ call: CAPPluginCall) { DispatchQueue.main.async { SpeechEngine.shared.stop(); call.resolve() } }

    // MARK: offline

    @objc func offlineStatus(_ call: CAPPluginCall) {
        DispatchQueue.global(qos: .utility).async { call.resolve(OfflineStore.shared.status()) }
    }

    @objc func tafsirGet(_ call: CAPPluginCall) {
        let s = call.getInt("surah") ?? 1
        DispatchQueue.global(qos: .userInitiated).async { call.resolve(["json": OfflineStore.shared.tafsirJSON(s)]) }
    }

    @objc func offlineDownload(_ call: CAPPluginCall) {
        let ok = OfflineStore.shared.startDownload(kind: call.getString("kind") ?? "audio", key: call.getString("key") ?? "",
                                                   from: call.getInt("from") ?? 1, to: call.getInt("to") ?? 114)
        Reminders.shared.requestPermission()
        call.resolve(["ok": ok])
    }

    @objc func offlineCancel(_ call: CAPPluginCall) { OfflineStore.shared.cancelDownload(); call.resolve() }
    @objc func offlineClear(_ call: CAPPluginCall) { call.resolve(["ok": OfflineStore.shared.clear(call.getString("what") ?? "all")]) }

    @objc func cachePage(_ call: CAPPluginCall) {
        let ed = call.getString("edition") ?? "hafs-kfqc", num = call.getString("num") ?? "001"
        OfflineStore.shared.cachePage(ed, num) { [weak self] ok in
            if ok { self?.notifyListeners("pageCached", data: ["edition": ed, "num": num]) }
        }
        call.resolve()
    }

    @objc func cachedPages(_ call: CAPPluginCall) {
        let ed = call.getString("edition") ?? "hafs-kfqc"
        DispatchQueue.global(qos: .utility).async { call.resolve(["pages": OfflineStore.shared.cachedPages(ed)]) }
    }

    // MARK: backup / share

    private var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    @objc func autoBackup(_ call: CAPPluginCall) {
        let json = call.getString("json") ?? ""
        DispatchQueue.global(qos: .utility).async {
            let f = self.documents.appendingPathComponent("hifz_quran_auto_backup.json")
            if (try? json.data(using: .utf8)?.write(to: f, options: .atomic)) != nil {
                UserDefaults.standard.set(Date().timeIntervalSince1970 * 1000, forKey: "auto_backup_time")
            }
            call.resolve()
        }
    }

    @objc func autoBackupInfo(_ call: CAPPluginCall) {
        call.resolve([
            "location": "تطبيق الملفات ← على iPhone ← أسهل نظام لحفظ القرآن",
            "time": UserDefaults.standard.double(forKey: "auto_backup_time"),
        ])
    }

    @objc func saveBackup(_ call: CAPPluginCall) {
        let json = call.getString("json") ?? ""
        let name = call.getString("fileName") ?? "hifz_quran_backup.json"
        let f = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard (try? json.data(using: .utf8)?.write(to: f, options: .atomic)) != nil else { call.resolve(["ok": false]); return }
        present(items: [f]) { ok in call.resolve(["ok": ok]) }
    }

    @objc func share(_ call: CAPPluginCall) {
        present(items: [call.getString("text") ?? ""]) { _ in call.resolve() }
    }

    private func present(items: [Any], done: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            guard let vc = self.bridge?.viewController else { done(false); return }
            let a = UIActivityViewController(activityItems: items, applicationActivities: nil)
            a.completionWithItemsHandler = { _, completed, _, _ in done(completed) }
            if let pop = a.popoverPresentationController {   // iPad
                pop.sourceView = vc.view
                pop.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.midY, width: 1, height: 1)
                pop.permittedArrowDirections = []
            }
            vc.present(a, animated: true)
        }
    }
}

/// Instantiated by name from AppDelegate (which cannot import this module) so the background
/// download session is re-created when iOS wakes the app for download events.
@objc(QuranBackgroundHook)
public class QuranBackgroundHook: NSObject {
    public override init() {
        super.init()
        _ = OfflineStore.shared
        NotificationCenter.default.addObserver(forName: Notification.Name("QuranBackgroundSessionEvents"), object: nil, queue: .main) { n in
            if let h = n.userInfo?["handler"] as? () -> Void { OfflineStore.shared.backgroundCompletion = h }
        }
    }
}
