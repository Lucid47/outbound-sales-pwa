import Foundation
#if os(iOS)
import UIKit
import UserNotifications
#endif

public enum GroupSmsScheduleAction: String, Sendable {
    case open
    case sendNow
    case snoozeTenMinutes
    case cancel
}

public struct GroupSmsScheduleNotificationEvent: Sendable {
    public var campaignId: String
    public var action: GroupSmsScheduleAction

    public init(campaignId: String, action: GroupSmsScheduleAction) {
        self.campaignId = campaignId
        self.action = action
    }
}

public extension Notification.Name {
    static let outboundSalesScheduledGroupSmsAction = Notification.Name("OutboundSalesScheduledGroupSmsAction")
}

public enum GroupSmsScheduleNotificationError: LocalizedError {
    case permissionDenied
    case invalidDate

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "예약 알림을 사용하려면 알림 권한이 필요합니다."
        case .invalidDate:
            return "현재 시각보다 뒤의 예약 시간을 선택하세요."
        }
    }
}

public enum GroupSmsScheduleNotificationService {
    public static let categoryIdentifier = "SOHEE_GROUP_SMS_SCHEDULED"
    public static let sendActionIdentifier = "SOHEE_GROUP_SMS_SEND_NOW"
    public static let snoozeActionIdentifier = "SOHEE_GROUP_SMS_SNOOZE_10"
    public static let cancelActionIdentifier = "SOHEE_GROUP_SMS_CANCEL"
    public static let campaignIdUserInfoKey = "campaignId"

    public static var currentDeviceIdentifier: String? {
        #if os(iOS)
        UIDevice.current.identifierForVendor?.uuidString
        #else
        nil
        #endif
    }

    public static func registerNotificationCategory() {
        #if os(iOS)
        let send = UNNotificationAction(
            identifier: sendActionIdentifier,
            title: "발송 시작",
            options: [.foreground]
        )
        let snooze = UNNotificationAction(
            identifier: snoozeActionIdentifier,
            title: "10분 뒤",
            options: [.foreground]
        )
        let cancel = UNNotificationAction(
            identifier: cancelActionIdentifier,
            title: "예약 취소",
            options: [.foreground, .destructive]
        )
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [send, snooze, cancel],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        #endif
    }

    @discardableResult
    public static func schedule(
        campaignId: String,
        title: String,
        recipientCount: Int,
        at date: Date
    ) async throws -> String {
        guard date > Date().addingTimeInterval(5) else {
            throw GroupSmsScheduleNotificationError.invalidDate
        }

        #if os(iOS)
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        var authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        if settings.authorizationStatus == .notDetermined {
            authorized = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        }
        guard authorized else {
            throw GroupSmsScheduleNotificationError.permissionDenied
        }

        let identifier = notificationIdentifier(for: campaignId)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "단체문자 예약 시간이 되었습니다"
        content.body = "\(title) · \(recipientCount)명"
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = [campaignIdUserInfoKey: campaignId]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await center.add(request)
        return identifier
        #else
        throw GroupSmsScheduleNotificationError.permissionDenied
        #endif
    }

    public static func cancel(notificationIdentifier: String?) {
        #if os(iOS)
        guard let notificationIdentifier, !notificationIdentifier.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [notificationIdentifier])
        #endif
    }

    public static func action(for notificationActionIdentifier: String) -> GroupSmsScheduleAction {
        switch notificationActionIdentifier {
        case sendActionIdentifier:
            return .sendNow
        case snoozeActionIdentifier:
            return .snoozeTenMinutes
        case cancelActionIdentifier:
            return .cancel
        default:
            return .open
        }
    }

    public static func campaignId(from userInfo: [AnyHashable: Any]) -> String? {
        userInfo[campaignIdUserInfoKey] as? String
    }

    private static func notificationIdentifier(for campaignId: String) -> String {
        "group-sms.schedule.\(campaignId)"
    }
}
