import OutboundSalesNative
import SwiftUI
import UIKit
import UserNotifications

@main
final class AppDelegate: UIResponder, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        GroupSmsScheduleNotificationService.registerNotificationCategory()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Self.postScheduledCampaignAction(response)
        completionHandler()
    }

    static func postScheduledCampaignAction(_ response: UNNotificationResponse) {
        guard let campaignId = GroupSmsScheduleNotificationService.campaignId(
            from: response.notification.request.content.userInfo
        ) else { return }
        let event = GroupSmsScheduleNotificationEvent(
            campaignId: campaignId,
            action: GroupSmsScheduleNotificationService.action(for: response.actionIdentifier)
        )
        NotificationCenter.default.post(name: .outboundSalesScheduledGroupSmsAction, object: event)
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

@objc(SceneDelegate)
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: OutboundSalesRootView())
        self.window = window
        window.makeKeyAndVisible()

        if let url = connectionOptions.urlContexts.first?.url {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .outboundSalesOpenURL, object: url)
            }
        }
        if let response = connectionOptions.notificationResponse {
            DispatchQueue.main.async {
                AppDelegate.postScheduledCampaignAction(response)
            }
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        NotificationCenter.default.post(name: .outboundSalesOpenURL, object: url)
    }
}
