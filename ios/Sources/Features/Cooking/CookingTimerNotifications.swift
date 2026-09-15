import AudioToolbox
import UIKit
import UserNotifications

final class CookingTimerNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = CookingTimerNotifications()
    private let center = UNUserNotificationCenter.current()
    @MainActor private var feedback: UINotificationFeedbackGenerator?

    func configure() { center.delegate = self }

    @MainActor
    func cancel(_ store: SessionStore) {
        let identifiers = store.graph.order.map { "cooking-timer.\(store.graph.recipe.id)." + $0 }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    @MainActor
    func sync(_ store: SessionStore) async {
        let prefix = "cooking-timer.\(store.graph.recipe.id)."
        let identifiers = store.graph.order.map { prefix + $0 }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        guard !store.recipeRemoved, !store.runningTimerIDs.isEmpty else { return }

        let settings = await center.notificationSettings()
        var allowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        if settings.authorizationStatus == .notDetermined {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) == true
        }
        guard allowed, !store.recipeRemoved else { return }

        for id in store.runningTimerIDs {
            guard !store.recipeRemoved else {
                cancel(store)
                return
            }
            guard let timer = store.session.progress.timers[id], timer.checkAt > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(store.cell(id).label) · Check now"
            content.body = store.graph.recipe.title
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, timer.checkAt.timeIntervalSinceNow),
                repeats: false
            )
            try? await center.add(UNNotificationRequest(identifier: prefix + id, content: content, trigger: trigger))
        }
    }

    @MainActor
    func prepareForegroundAlert() {
        guard UIApplication.shared.applicationState == .active,
              !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        if feedback == nil { feedback = UINotificationFeedbackGenerator() }
        feedback?.prepare()
    }

    @MainActor
    func foregroundAlert() {
        guard UIApplication.shared.applicationState == .active,
              !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        if feedback == nil { feedback = UINotificationFeedbackGenerator() }
        feedback?.notificationOccurred(.warning)
        AudioServicesPlaySystemSound(1005)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }
}
