import Foundation
import Observation

/// Persistent, observable application settings backed by UserDefaults.
@MainActor
@Observable
final class EaveSettings {
    private let defaults: UserDefaults

    nonisolated static let secondRowItemsPerRowRange: ClosedRange<Int> = 3...16
    nonisolated static let defaultSecondRowItemsPerRow: Int = 8
    nonisolated static let defaultAutoRehideDelaySeconds: Double = 8.0

    nonisolated static func clampedItemsPerRow(_ value: Int) -> Int {
        min(max(value, secondRowItemsPerRowRange.lowerBound), secondRowItemsPerRowRange.upperBound)
    }

    private enum Key {
        static let appearanceMode = "eave.appearanceMode"
        static let rehideAutomatically = "eave.rehideAutomatically"
        static let expandOnEaveHover = "eave.expandOnEaveHover"
        static let hoverDelaySeconds = "eave.hoverDelaySeconds"
        static let hoverDisplayMode = "eave.hoverDisplayMode"
        static let secondRowLayoutMode = "eave.secondRowLayoutMode"
        static let secondRowItemsPerRow = "eave.secondRowItemsPerRow"

        static let enableNotchPeek = "eave.enableNotchPeek"
        static let peekDurationSeconds = "eave.peekDurationSeconds"
        static let watchHiddenAppsAutomatically = "eave.watchHiddenAppsAutomatically"
        static let watchedBundleIDs = "eave.watchedBundleIDs"
        static let enableNotchBridge = "eave.enableNotchBridge"

        static let hotKeyPrefix = "eave.hotkey."
    }

    // MARK: - General & Menu Bar

    var appearanceMode: AppAppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: Key.appearanceMode) }
    }

    /// Unified auto-rehide preference: automatically collapses expanded items after inactivity or app switch.
    var rehideAutomatically: Bool {
        didSet { defaults.set(rehideAutomatically, forKey: Key.rehideAutomatically) }
    }

    var expandOnEaveHover: Bool {
        didSet { defaults.set(expandOnEaveHover, forKey: Key.expandOnEaveHover) }
    }

    var hoverDelaySeconds: Double {
        didSet { defaults.set(hoverDelaySeconds, forKey: Key.hoverDelaySeconds) }
    }

    var hoverDisplayMode: HoverDisplayMode {
        didSet { defaults.set(hoverDisplayMode.rawValue, forKey: Key.hoverDisplayMode) }
    }

    var secondRowLayoutMode: SecondRowLayoutMode {
        didSet { defaults.set(secondRowLayoutMode.rawValue, forKey: Key.secondRowLayoutMode) }
    }

    var secondRowItemsPerRow: Int {
        didSet {
            let clamped = Self.clampedItemsPerRow(secondRowItemsPerRow)
            if secondRowItemsPerRow != clamped {
                secondRowItemsPerRow = clamped
                return
            }
            defaults.set(clamped, forKey: Key.secondRowItemsPerRow)
        }
    }

    // MARK: - Notch Notifications & Signals

    /// Unified master toggle controlling Notch Peek, ambient edge indicators, and menu-bar status watchers.
    var enableNotchPeek: Bool {
        didSet { defaults.set(enableNotchPeek, forKey: Key.enableNotchPeek) }
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

    // MARK: - Shortcuts

    private(set) var hotKeys: [HotKeyAction: KeyCombo] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let rawAppearance = defaults.string(forKey: Key.appearanceMode),
           let appearance = AppAppearanceMode(rawValue: rawAppearance) {
            self.appearanceMode = appearance
        } else {
            self.appearanceMode = .system
        }

        self.rehideAutomatically = defaults.object(forKey: Key.rehideAutomatically) as? Bool ?? true
        self.expandOnEaveHover = defaults.object(forKey: Key.expandOnEaveHover) as? Bool ?? true
        self.hoverDelaySeconds = defaults.object(forKey: Key.hoverDelaySeconds) as? Double ?? 0.20

        if let rawMode = defaults.string(forKey: Key.hoverDisplayMode),
           let mode = HoverDisplayMode(rawValue: rawMode) {
            self.hoverDisplayMode = mode
        } else {
            self.hoverDisplayMode = .inline
        }

        if let rawLayout = defaults.string(forKey: Key.secondRowLayoutMode),
           let layout = SecondRowLayoutMode(rawValue: rawLayout) {
            self.secondRowLayoutMode = layout
        } else {
            self.secondRowLayoutMode = .horizontalScroll
        }

        if let storedPerRow = defaults.object(forKey: Key.secondRowItemsPerRow) as? Int {
            self.secondRowItemsPerRow = Self.clampedItemsPerRow(storedPerRow)
        } else {
            self.secondRowItemsPerRow = Self.defaultSecondRowItemsPerRow
        }

        self.enableNotchPeek = defaults.object(forKey: Key.enableNotchPeek) as? Bool ?? true
        self.peekDurationSeconds = defaults.object(forKey: Key.peekDurationSeconds) as? Double ?? 4.5
        self.watchHiddenAppsAutomatically = defaults.object(forKey: Key.watchHiddenAppsAutomatically) as? Bool ?? true
        self.watchedBundleIDs = defaults.stringArray(forKey: Key.watchedBundleIDs) ?? []
        self.enableNotchBridge = defaults.object(forKey: Key.enableNotchBridge) as? Bool ?? true

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
