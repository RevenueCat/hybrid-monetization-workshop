import SwiftUI

@MainActor
protocol AppIconClient {
    var supportsAlternateIcons: Bool { get }
    var alternateIconName: String? { get }
    func changeIcon(to name: String?) async throws
}

extension UIApplication: AppIconClient {
    func changeIcon(to name: String?) async throws {
        try await setAlternateIconName(name)
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }
    var scheme: ColorScheme? { self == .system ? nil : self == .dark ? .dark : .light }
}

@MainActor
final class AppearanceStore: ObservableObject {
    /// Availability is supplied by the caller; the baseline allows every theme.
    @Published var availableThemes: Set<AppTheme> { didSet { syncAppIcon() } }
    @Published private(set) var preferredTheme: AppTheme
    var theme: AppTheme {
        get { availableThemes.contains(preferredTheme) ? preferredTheme : .original }
        set { preferredTheme = newValue; defaults.set(newValue.rawValue, forKey: "theme"); syncAppIcon() }
    }
    @Published private(set) var iconError: String?
    @Published private(set) var isChangingIcon = false
    private let iconClient: AppIconClient
    private var iconsActive = false
    var supportsThemeIcons: Bool { iconClient.supportsAlternateIcons }
    private var desiredIcon: String? { theme.alternateIconName }
    @Published var mode: AppearanceMode { didSet { defaults.set(mode.rawValue, forKey: "mode") } }
    @Published var density: GridDensity { didSet { defaults.set(density.rawValue, forKey: "density") } }
    @Published var keepScreenAwake: Bool { didSet { defaults.set(keepScreenAwake, forKey: "keepScreenAwake") } }
    var screenOnActionTitle: String { keepScreenAwake ? "Allow auto-lock" : "Keep screen on" }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard, iconClient: AppIconClient = UIApplication.shared,
         availableThemes: Set<AppTheme> = Set(AppTheme.allCases)) {
        self.availableThemes = availableThemes
        self.defaults = defaults
        self.iconClient = iconClient
        keepScreenAwake = defaults.bool(forKey: "keepScreenAwake")
        density = GridDensity(rawValue: defaults.string(forKey: "density") ?? "") ?? .compact
        preferredTheme = AppTheme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .original
        mode = AppearanceMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .system
    }

    func setIconsActive(_ active: Bool) {
        iconsActive = active
        if active && iconError == nil { syncAppIcon() }
    }

    func syncAppIcon() {
        guard iconsActive, supportsThemeIcons, !isChangingIcon else { return }
        let requested = desiredIcon
        iconError = nil
        guard iconClient.alternateIconName != requested else { return }
        isChangingIcon = true
        Task {
            do {
                try await iconClient.changeIcon(to: requested)
            } catch {
                iconError = "The app icon couldn’t be changed. Your theme is still applied."
            }
            isChangingIcon = false
            // Serialize changes and keep the latest selection if it changed mid-request.
            if desiredIcon != requested { syncAppIcon() }
        }
    }
}

/// A local table-spacing choice that leaves the saved preference untouched.
private struct GridDensityOverrideKey: EnvironmentKey {
    static let defaultValue: GridDensity? = nil
}

extension EnvironmentValues {
    var gridDensityOverride: GridDensity? {
        get { self[GridDensityOverrideKey.self] }
        set { self[GridDensityOverrideKey.self] = newValue }
    }
}
