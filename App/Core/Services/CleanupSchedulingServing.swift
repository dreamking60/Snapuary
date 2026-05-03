import Foundation
import UserNotifications

protocol CleanupSchedulingServing {
    func authorizationStatus() async -> CleanupNotificationAuthorizationStatus
    func requestAuthorization() async -> CleanupNotificationAuthorizationStatus
    func scheduleNextCleanupReminder(for assets: [MediaAsset], now: Date) async throws -> CleanupReminderSchedule?
}

enum CleanupNotificationAuthorizationStatus: String, Hashable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    var canSchedule: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            true
        case .notDetermined, .denied:
            false
        }
    }
}

struct CleanupReminderSchedule: Hashable {
    let title: String
    let scheduledAt: Date
    let candidateCount: Int
}

actor UserNotificationCleanupScheduler: CleanupSchedulingServing {
    private let center: UNUserNotificationCenter
    private let requestIdentifier = "snapuary.cleanup.next"

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> CleanupNotificationAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus.snapuaryStatus
    }

    func requestAuthorization() async -> CleanupNotificationAuthorizationStatus {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return .denied
        }

        return await authorizationStatus()
    }

    func scheduleNextCleanupReminder(for assets: [MediaAsset], now: Date = .now) async throws -> CleanupReminderSchedule? {
        center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])

        let eligibleAssets = assets
            .filter { !$0.isProtectedFromCleanup }
            .filter(\.isScreenshot)

        let futureCandidates = eligibleAssets
            .compactMap { asset -> (MediaAsset, Date)? in
                guard let expirationDate = asset.expirationDate, expirationDate > now else {
                    return nil
                }
                return (asset, expirationDate)
            }
            .sorted { $0.1 < $1.1 }

        guard let firstExpiration = futureCandidates.first?.1 else {
            return nil
        }

        let sameDayCount = futureCandidates.filter {
            Calendar.current.isDate($0.1, inSameDayAs: firstExpiration)
        }.count

        let content = UNMutableNotificationContent()
        content.title = "Screenshot Cleanup Due"
        content.body = sameDayCount == 1
            ? "One screenshot reaches its cleanup date today."
            : "\(sameDayCount) screenshots reach their cleanup date today."
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: firstExpiration
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: requestIdentifier,
            content: content,
            trigger: trigger
        )
        try await center.add(request)

        return CleanupReminderSchedule(
            title: content.title,
            scheduledAt: firstExpiration,
            candidateCount: sameDayCount
        )
    }
}

private extension UNAuthorizationStatus {
    var snapuaryStatus: CleanupNotificationAuthorizationStatus {
        switch self {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .authorized:
            .authorized
        case .provisional:
            .provisional
        case .ephemeral:
            .ephemeral
        @unknown default:
            .denied
        }
    }
}
