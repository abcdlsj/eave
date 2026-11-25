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
        let domain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]
        let spacing = domain[Self.spacingKey] as? Int
        let padding = domain[Self.paddingKey] as? Int
        config = MenuBarSpacingConfig(spacing: spacing, selectionPadding: padding)
    }

    func apply(spacing: Int?, selectionPadding: Int?) {
        var domain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]

        if let spacing {
            domain[Self.spacingKey] = max(2, min(spacing, 24))
        } else {
            domain.removeValue(forKey: Self.spacingKey)
        }

        if let selectionPadding {
            domain[Self.paddingKey] = max(2, min(selectionPadding, 20))
        } else {
            domain.removeValue(forKey: Self.paddingKey)
        }

        UserDefaults.standard.setPersistentDomain(domain, forName: UserDefaults.globalDomain)
        UserDefaults.standard.synchronize()
        reload()
    }

    func resetToSystemDefault() {
        apply(spacing: nil, selectionPadding: nil)
    }
}
