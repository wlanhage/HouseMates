import SwiftUI
import UIKit

@main
struct KalenderSpikeApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(lab: appDelegate.lab)
        }
    }
}

/// Path D: a silent push wakes the app in the background and it mirrors the event into the device calendar.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let lab = CalendarLab()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        lab.note("Registrerad för push")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        lab.note("Push-registrering misslyckades: \(error.localizedDescription)")
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard let payload = userInfo["housemates"] as? [String: Any], let title = payload["title"] as? String else {
            return .noData
        }
        let inHours = payload["inHours"] as? Double ?? 1
        let state = application.applicationState == .background ? "bakgrund" : "förgrund"
        return lab.mirrorEvent(titled: title, inHours: inHours, wokenIn: state) ? .newData : .failed
    }
}
