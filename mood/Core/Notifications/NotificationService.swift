import Foundation
import UIKit
import UserNotifications

/// Where the system permission stands, as the settings screen shows it.
enum NotificationAuthorizationState: Equatable {
    case unknown
    case notDetermined
    case denied
    case authorized
}

/// Local notifications (`UNUserNotificationCenter`) for messages the sync loop brings in.
/// There is no push server yet (that needs an Apple Developer account), so a notification only
/// appears while the app is running, in the foreground on another room or in the background.
///
/// This type only talks to the system. Whether a message deserves a notification is decided by
/// `NotificationDecision`; the store feeds the result in.
@MainActor
final class NotificationService: NSObject {
    static let shared = NotificationService()

    /// Set by the store: the user tapped a notification of this room.
    var onOpenRoom: ((String) -> Void)? {
        didSet { deliverPendingTap() }
    }

    /// A tap that arrived before the store was listening (cold launch from a notification).
    private var pendingTapRoomId: String?
    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    /// True while the app is frontmost. A banner for the open room is useless then.
    var isAppActive: Bool {
        UIApplication.shared.applicationState == .active
    }

    // MARK: Permission

    func authorizationState() async -> NotificationAuthorizationState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .authorized
        @unknown default: return .unknown
        }
    }

    /// Shows the system prompt the first time; afterwards answers from the stored choice.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: Posting

    func post(_ candidate: NotificationCandidate, playSound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = candidate.title
        content.body = candidate.preview
        content.threadIdentifier = candidate.roomId
        content.userInfo = ["roomId": candidate.roomId, "eventId": candidate.eventId]
        if playSound { content.sound = .default }
        let request = UNNotificationRequest(identifier: candidate.eventId, content: content, trigger: nil)
        center.add(request) { _ in }
    }

    /// Clears the banners of a room once the user is looking at it.
    func removeDelivered(roomId: String) {
        Task {
            let delivered = await center.deliveredNotifications()
            let ids = delivered
                .filter { $0.request.content.threadIdentifier == roomId }
                .map { $0.request.identifier }
            guard !ids.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    func removeAllDelivered() {
        center.removeAllDeliveredNotifications()
    }

    // MARK: Badge

    func setBadge(_ count: Int) {
        center.setBadgeCount(max(0, count)) { _ in }
    }

    // MARK: Taps

    fileprivate func handleTap(roomId: String) {
        pendingTapRoomId = roomId
        deliverPendingTap()
    }

    private func deliverPendingTap() {
        guard let roomId = pendingTapRoomId, let onOpenRoom else { return }
        pendingTapRoomId = nil
        onOpenRoom(roomId)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {

    /// The app is in front: still show messages from rooms other than the open one
    /// (the store never posts the open room's own messages).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let roomId = response.notification.request.content.userInfo["roomId"] as? String else { return }
        await MainActor.run { NotificationService.shared.handleTap(roomId: roomId) }
    }
}
