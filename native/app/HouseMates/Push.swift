import Observation
import OSLog
import UIKit
import UserNotifications

/// Pushnotiser: enhetstoken till servern, banner även när appen är öppen och rätt flik vid tryck.
/// Riktig leverans kräver APNs-nyckel och Push-rättigheten (betalt Apple-konto), se native/README.md.
@MainActor
@Observable
final class Push: NSObject {
    static let shared = Push()

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    var openedTab: AppTab?

    @ObservationIgnored private var deviceToken: String?
    private let logger = Logger(subsystem: "se.housemates.app", category: "push")

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestPermission() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorization()
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// Vid start för den som redan sagt ja, så att tokenen alltid är aktuell på servern.
    func registerIfAllowed() async {
        await refreshAuthorization()
        if authorization == .authorized { UIApplication.shared.registerForRemoteNotifications() }
    }

    func didRegister(deviceToken data: Data) async {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        await uploadToken()
    }

    func uploadToken() async {
        guard let deviceToken, Backend.client.auth.currentUser != nil else { return }
        do {
            try await Backend.client.rpc("register_device", params: ["p_token": deviceToken]).execute()
        } catch {
            logger.error("Kunde inte spara enhetstoken: \(error.localizedDescription, privacy: .public)")
        }
    }

    func unregisterDevice() async {
        guard let deviceToken else { return }
        _ = try? await Backend.client.rpc("unregister_device", params: ["p_token": deviceToken]).execute()
    }
}

extension Push: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let tab = (response.notification.request.content.userInfo["url"] as? String).flatMap(AppTab.init(rawValue:))
        await MainActor.run { openedTab = tab }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger(subsystem: "se.housemates.app", category: "push")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = Push.shared
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await Push.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.notice("Ingen push-token (kräver Push-rättigheten): \(error.localizedDescription, privacy: .public)")
    }
}
