import Foundation
import Observation

/// Persistent, observable application settings backed by UserDefaults.
@MainActor
@Observable
final class EaveSettings {
    private let defaults: UserDefaults

    private enum Key {
        static let enableAlwaysHiddenSection = "eave.enableAlwaysHiddenSection"
        static let rehideAutomatically = "eave.rehideAutomatically"
        static let rehideDelaySeconds = "eave.rehideDelaySeconds"
        static let rehideOnAppSwitch = "eave.rehideOnAppSwitch"
        static let expandOnMenuBarScroll = "eave.expandOnMenuBarScroll"
        static let expandOnMenuBarHover = "eave.expandOnMenuBarHover"
        static let hoverDelaySeconds = "eave.hoverDelaySeconds"
        static let useNotchBarOnToggle = "eave.useNotchBarOnToggle"

        static let enableNotchPeek = "eave.enableNotchPeek"
        static let enableAmbientIndicators = "eave.enableAmbientIndicators"
        static let peekDurationSeconds = "eave.peekDurationSeconds"
        static let watchHiddenAppsAutomatically = "eave.watchHiddenAppsAutomatically"
        static let watchedBundleIDs = "eave.watchedBundleIDs"
        static let enableNotchBridge = "eave.enableNotchBridge"
        static let enableMenuBarAXWatcher = "eave.enableMenuBarAXWatcher"

        static let enableLiveIconCapture = "eave.enableLiveIconCapture"
        static let hotKeyPrefix = "eave.hotkey."
    }

    // MARK: - Phase 1: Menu Bar Hiding

    var enableAlwaysHiddenSection: Bool {
        didSet { defaults.set(enableAlwaysHiddenSection, forKey: Key.enableAlwaysHiddenSection) }
    }

    var rehideAutomatically: Bool {
        didSet { defaults.set(rehideAutomatically, forKey: Key.rehideAutomatically) }
    }

    var rehideDelaySeconds: Double {
        didSet { defaults.set(rehideDelaySeconds, forKey: Key.rehideDelaySeconds) }
    }

    var rehideOnAppSwitch: Bool {
        didSet { defaults.set(rehideOnAppSwitch, forKey: Key.rehideOnAppSwitch) }
    }

    var expandOnMenuBarScroll: Bool {
        didSet { defaults.set(expandOnMenuBarScroll, forKey: Key.expandOnMenuBarScroll) }
    }

    var expandOnMenuBarHover: Bool {
        didSet { defaults.set(expandOnMenuBarHover, forKey: Key.expandOnMenuBarHover) }
    }

    var hoverDelaySeconds: Double {
        didSet { defaults.set(hoverDelaySeconds, forKey: Key.hoverDelaySeconds) }
    }

    /// When enabled, clicking the Eave anchor icon opens the Notch Bar drawer instead of expanding inline.
    var useNotchBarOnToggle: Bool {
        didSet { defaults.set(useNotchBarOnToggle, forKey: Key.useNotchBarOnToggle) }
    }

    // MARK: - Phase 2: Notch & Signals

    var enableNotchPeek: Bool {
        didSet { defaults.set(enableNotchPeek, forKey: Key.enableNotchPeek) }
    }

    var enableAmbientIndicators: Bool {
        didSet { defaults.set(enableAmbientIndicators, forKey: Key.enableAmbientIndicators) }
    }

    var peekDurationSeconds: Double {
        didSet { defaults.set(peekDurationSeconds, forKey: Key.peekDurationSeconds) }
    }

    var watchHiddenAppsAutomatically: Bool {
        didSet { defaults.set(watchHiddenAppsAutomatically, forKey: Key.watchHiddenAppsAutomatically) }
    }

    /// Additional app bundle IDs explicitly watched for Dock badges regardless of menu bar section.
    var watchedBundleIDs: [String] {
        didSet { defaults.set(watchedBundleIDs, forKey: Key.watchedBundleIDs) }
    }

    var enableNotchBridge: Bool {
        didSet { defaults.set(enableNotchBridge, forKey: Key.enableNotchBridge) }
    }

    var enableMenuBarAXWatcher: Bool {
        didSet { defaults.set(enableMenuBarAXWatcher, forKey: Key.enableMenuBarAXWatcher) }
    }

    // MARK: - Phase 3: Notch Bar Capture

    var enableLiveIconCapture: Bool {
        didSet { defaults.set(enableLiveIconCapture, forKey: Key.enableLiveIconCapture) }
    }

    // MARK: - Shortcuts

    private(set) var hotKeys: [HotKeyAction: KeyCombo] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Always-Hidden is opt-in so a single click expands every hidden icon out of the box.
        self.enableAlwaysHiddenSection = defaults.object(forKey: Key.enableAlwaysHiddenSection) as? Bool ?? false
        self.rehideAutomatically = defaults.object(forKey: Key.rehideAutomatically) as? Bool ?? true
        self.rehideDelaySeconds = defaults.object(forKey: Key.rehideDelaySeconds) as? Double ?? 8.0
        self.rehideOnAppSwitch = defaults.object(forKey: Key.rehideOnAppSwitch) as? Bool ?? true
        self.expandOnMenuBarScroll = defaults.object(forKey: Key.expandOnMenuBarScroll) as? Bool ?? true
        self.expandOnMenuBarHover = defaults.object(forKey: Key.expandOnMenuBarHover) as? Bool ?? false
        self.hoverDelaySeconds = defaults.object(forKey: Key.hoverDelaySeconds) as? Double ?? 0.35
        self.useNotchBarOnToggle = defaults.object(forKey: Key.useNotchBarOnToggle) as? Bool ?? false

        self.enableNotchPeek = defaults.object(forKey: Key.enableNotchPeek) as? Bool ?? true
        self.enableAmbientIndicators = defaults.object(forKey: Key.enableAmbientIndicators) as? Bool ?? true
        self.peekDurationSeconds = defaults.object(forKey: Key.peekDurationSeconds) as? Double ?? 4.5
        self.watchHiddenAppsAutomatically = defaults.object(forKey: Key.watchHiddenAppsAutomatically) as? Bool ?? true
        self.watchedBundleIDs = defaults.stringArray(forKey: Key.watchedBundleIDs) ?? []
        self.enableNotchBridge = defaults.object(forKey: Key.enableNotchBridge) as? Bool ?? true
        self.enableMenuBarAXWatcher = defaults.object(forKey: Key.enableMenuBarAXWatcher) as? Bool ?? true

        self.enableLiveIconCapture = defaults.object(forKey: Key.enableLiveIconCapture) as? Bool ?? true

        for action in HotKeyAction.allCases {
            if let data = defaults.data(forKey: Key.hotKeyPrefix + action.rawValue),
               let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
                hotKeys[action] = combo
            } else {
                hotKeys[action] = action.defaultCombo
            }
        }
    }

    func hotKey(for action: HotKeyAction) -> KeyCombo? {
        hotKeys[action]
    }

    func setHotKey(_ combo: KeyCombo?, for action: HotKeyAction) {
        hotKeys[action] = combo
        let key = Key.hotKeyPrefix + action.rawValue
        if let combo, let data = try? JSONEncoder().encode(combo) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func resetHotKeys() {
        for action in HotKeyAction.allCases {
            setHotKey(action.defaultCombo, for: action)
        }
    }

    func addWatchedBundleID(_ bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !watchedBundleIDs.contains(trimmed) else { return }
        watchedBundleIDs.append(trimmed)
    }

    func removeWatchedBundleID(_ bundleID: String) {
        watchedBundleIDs.removeAll { $0 == bundleID }
    }
}
