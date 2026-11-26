import Foundation
import Observation

/// Manages macOS global menu bar spacing keys (`NSStatusItemSpacing` and `NSStatusItemSelectionPadding`).
@MainActor
@Observable
final class MenuBarSpacingManager {
    private static let spacingKey = "NSStatusItemSpacing"
    private static let paddingKey = "NSStatusItemSelectionPadding"

    private(set) var config: MenuBarSpacingConfig = .systemDefault

    init() {
        reload()
    }

    func reload() {
        let spacing = Self.readGlobal(Self.spacingKey)
        let padding = Self.readGlobal(Self.paddingKey)
        config = MenuBarSpacingConfig(spacing: spacing, selectionPadding: padding)
    }

    func apply(spacing: Int?, selectionPadding: Int?) {
        // Write only these two keys. Rewriting the whole NSGlobalDomain could clobber changes other
        // processes made between our read and write.
        Self.writeGlobal(Self.spacingKey, spacing.map { max(2, min($0, 24)) })
        Self.writeGlobal(Self.paddingKey, selectionPadding.map { max(2, min($0, 20)) })
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        reload()
    }

    private static func readGlobal(_ key: String) -> Int? {
        CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Int
    }

    private static func writeGlobal(_ key: String, _ value: Int?) {
        CFPreferencesSetValue(
            key as CFString,
            value.map { $0 as CFNumber },
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
    }

    func resetToSystemDefault() {
        apply(spacing: nil, selectionPadding: nil)
    }
}
