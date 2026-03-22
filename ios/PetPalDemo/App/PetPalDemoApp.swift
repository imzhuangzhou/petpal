import SwiftUI
import UIKit
import UserNotifications

@main
struct PetPalDemoApp: App {
    @UIApplicationDelegateAdaptor(PetPalAppDelegate.self) private var appDelegate
    @StateObject private var appStore = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appStore)
        }
    }
}

final class PetPalAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
