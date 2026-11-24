import UIKit
import Capacitor

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = CAPBridgeViewController()
        window?.makeKeyAndVisible()

        SceneDelegateProxy.shared.scene(scene, willConnectTo: session, options: connectionOptions)
        if let item = connectionOptions.shortcutItem { storeShortcut(item) }
    }

    // Home-screen quick actions (long-press the app icon)
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        storeShortcut(shortcutItem)
        completionHandler(true)
    }

    private func storeShortcut(_ item: UIApplicationShortcutItem) {
        let value = item.type.hasSuffix("OPEN_MUSHAF") ? "mushaf" : "today"
        UserDefaults.standard.set(value, forKey: "pending_shortcut")
        NotificationCenter.default.post(name: Notification.Name("QuranShortcut"), object: nil)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        SceneDelegateProxy.shared.scene(scene, openURLContexts: URLContexts)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        SceneDelegateProxy.shared.scene(scene, continue: userActivity)
    }
}
