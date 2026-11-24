import Foundation
import UserNotifications

/// Daily reminders as local notifications with "done" / "snooze 30 min" buttons.
/// iOS cannot run code when a notification fires, so the next 14 days are scheduled ahead
/// and re-planned whenever the wird or the times change; a day already done is skipped.
final class Reminders: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Reminders()

    static let category = "WIRD_REMINDER"
    static let actionDone = "WIRD_DONE"
    static let actionSnooze = "WIRD_SNOOZE"
    static let pendingDoneKey = "pending_done"     // "tableId-day|yyyy-MM-dd", applied by the page

    private let center = UNUserNotificationCenter.current()
    private let d = UserDefaults.standard

    func setup() {
        center.delegate = self
        let done = UNNotificationAction(identifier: Self.actionDone, title: "✓ أتممت الورد", options: [])
        let snooze = UNNotificationAction(identifier: Self.actionSnooze, title: "ذكّرني بعد 30 دقيقة", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [done, snooze], intentIdentifiers: [], options: [])])
    }

    func requestPermission(_ done: ((Bool) -> Void)? = nil) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
            DispatchQueue.main.async { done?(ok) }
        }
    }

    static func today() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // MARK: data from the page

    func setTimes(_ t1: String, _ enabled2: Bool, _ t2: String) {
        d.set(t1, forKey: "reminder_time_1"); d.set(enabled2, forKey: "reminder_enabled_2"); d.set(t2, forKey: "reminder_time_2")
        reschedule()
    }

    func setWird(surah: String, detail: String) {
        d.set(surah, forKey: "widget_surah"); d.set(detail, forKey: "widget_detail")
    }

    func setStatus(key: String, doneDate: String) {
        d.set(key, forKey: "current_key")
        d.set(doneDate == Self.today() ? doneDate : "", forKey: "today_done_date")
        reschedule()
    }

    // MARK: scheduling

    private func body() -> String {
        let s = d.string(forKey: "widget_surah") ?? "سورة البقرة"
        let det = d.string(forKey: "widget_detail") ?? "افتح التطبيق لإتمام وردك اليومي"
        return "\(s) — \(det)"
    }

    func reschedule() {
        center.getPendingNotificationRequests { reqs in
            let old = reqs.map { $0.identifier }.filter { $0.hasPrefix("reminder-") }
            self.center.removePendingNotificationRequests(withIdentifiers: old)
            var times: [(String, String)] = [(self.d.string(forKey: "reminder_time_1") ?? "05:30", "تذكير ورد الحفظ اليومي")]
            if self.d.bool(forKey: "reminder_enabled_2") {
                times.append((self.d.string(forKey: "reminder_time_2") ?? "21:00", "تذكير المراجعة المسائية"))
            }
            let doneToday = (self.d.string(forKey: "today_done_date") ?? "") == Self.today()
            let cal = Calendar.current
            let now = Date()
            for dayOffset in 0..<14 {
                if dayOffset == 0 && doneToday { continue }
                guard let day = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
                for (i, (hhmm, title)) in times.enumerated() {
                    let parts = hhmm.split(separator: ":").compactMap { Int($0) }
                    var comps = cal.dateComponents([.year, .month, .day], from: day)
                    comps.hour = parts.count > 0 ? parts[0] : 5
                    comps.minute = parts.count > 1 ? parts[1] : 30
                    guard let fire = cal.date(from: comps), fire > now else { continue }
                    let c = UNMutableNotificationContent()
                    c.title = title
                    c.body = self.body()
                    c.sound = .default
                    c.categoryIdentifier = Self.category
                    let trig = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                    self.center.add(UNNotificationRequest(identifier: "reminder-\(dayOffset)-\(i)", content: c, trigger: trig))
                }
            }
        }
    }

    func showNow(title: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body()
        c.sound = .default
        c.categoryIdentifier = Self.category
        center.add(UNNotificationRequest(identifier: "reminder-test", content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }

    // MARK: delegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case Self.actionDone:
            if let key = d.string(forKey: "current_key") {
                d.set("\(key)|\(Self.today())", forKey: Self.pendingDoneKey)
                d.set(Self.today(), forKey: "today_done_date")
                reschedule()
                NotificationCenter.default.post(name: Notification.Name("QuranPendingDone"), object: nil)
            }
        case Self.actionSnooze:
            let c = UNMutableNotificationContent()
            c.title = "تذكير: ورد القرآن اليومي"
            c.body = body()
            c.sound = .default
            c.categoryIdentifier = Self.category
            center.add(UNNotificationRequest(identifier: "reminder-snooze", content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 30 * 60, repeats: false)))
        default:
            break
        }
        completionHandler()
    }

    func consumePendingDone() -> String {
        let v = d.string(forKey: Self.pendingDoneKey) ?? ""
        if !v.isEmpty { d.removeObject(forKey: Self.pendingDoneKey) }
        return v
    }
}
