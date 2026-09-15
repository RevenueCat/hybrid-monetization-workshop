import SwiftUI

enum CookingScreenAwakePolicy {
    static func preventsLocking(enabled: Bool, visible: Bool, phase: ScenePhase) -> Bool {
        enabled && visible && phase == .active
    }
}

/// Scope to the cooking screen so inspecting its sheets preserves the preference.
struct CookingScreenAwake: ViewModifier {
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(\.scenePhase) private var phase
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .onAppear { visible = true; update(visible: true) }
            .onDisappear { visible = false; update(visible: false) }
            .onChange(of: phase) { _, _ in update(visible: visible) }
            .onChange(of: appearance.keepScreenAwake) { _, _ in update(visible: visible) }
    }

    private func update(visible: Bool) {
        UIApplication.shared.isIdleTimerDisabled = CookingScreenAwakePolicy.preventsLocking(
            enabled: appearance.keepScreenAwake, visible: visible, phase: phase)
    }
}

struct KeepScreenOnButton: View {
    @EnvironmentObject private var appearance: AppearanceStore
    private var actionTitle: String { appearance.screenOnActionTitle }

    var body: some View {
        Button {
            appearance.keepScreenAwake.toggle()
        } label: {
            Image(systemName: appearance.keepScreenAwake ? "sun.max.fill" : "sun.max")
                .font(.system(size: 20, weight: .medium))
                .frame(width: 48, height: 48)
                .foregroundStyle(Color(uiColor: appearance.theme.ink))
                .background(Color(uiColor: appearance.theme.surface), in: Circle())
                .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
        }
        .accessibilityLabel(actionTitle)
        .accessibilityValue(appearance.keepScreenAwake ? "On" : "Off")
        .accessibilityIdentifier("grid.keepScreenOn")
        .help(actionTitle)
    }
}

struct CookingNotificationPill: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let icon: String
    let text: String
    var additionalCount = 0
    var dismissalInterval: DateInterval? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
            if additionalCount > 0 { Text("+\(additionalCount)").monospacedDigit() }
        }
        .themeFont(appearance.theme, style: .callout, emphasized: true)
        .foregroundStyle(Color(uiColor: appearance.theme.ink))
        .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 44)
        .background {
            ZStack(alignment: .leading) {
                Color(uiColor: appearance.theme.surface)
                if let interval = dismissalInterval {
                    TimelineView(.periodic(from: interval.start, by: reduceMotion ? 1 : 1.0 / 30)) { context in
                        GeometryReader { geometry in
                            let fraction = min(1, max(0, context.date.timeIntervalSince(interval.start) / max(interval.duration, 0.001)))
                            Rectangle()
                                .fill(Color(uiColor: appearance.theme.pendingRecipeTint))
                                .frame(width: geometry.size.width * fraction)
                        }
                    }
                }
            }
            .clipShape(Capsule())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .overlay(Capsule().stroke(Color(uiColor: appearance.theme.line), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }
}

struct ScreenOnFeedback: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @State private var showsFeedback = false
    @State private var feedbackRevision = 0
    @State private var dismissalInterval: DateInterval?

    var body: some View {
        Group {
            if showsFeedback {
                CookingNotificationPill(icon: appearance.keepScreenAwake ? "sun.max.fill" : "sun.max",
                                        text: appearance.keepScreenAwake ? "Screen will stay on" : "Automatic locking restored",
                                        dismissalInterval: dismissalInterval)
                    .accessibilityIdentifier("screenOn.feedback")
            }
        }
        .allowsHitTesting(false)
        .onChange(of: appearance.keepScreenAwake) { _, _ in
            showsFeedback = true
            feedbackRevision += 1
        }
        .task(id: feedbackRevision) {
            guard showsFeedback else { return }
            let interval = DateInterval(start: Date(), duration: 3)
            dismissalInterval = interval
            do { try await Task.sleep(for: .seconds(max(0, interval.end.timeIntervalSinceNow))) } catch { return }
            showsFeedback = false
            dismissalInterval = nil
        }
    }
}
