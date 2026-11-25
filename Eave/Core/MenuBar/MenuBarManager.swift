import AppKit
import Foundation
import Observation

/// Phase 1 core: manages the three-section menu bar layout (Visible / Hidden / Always-Hidden)
/// using standard NSStatusItem separator length inflation — zero private APIs, zero permissions required.
@MainActor
@Observable
final class MenuBarManager: NSObject {
    private static let collapsedSeparatorLength: CGFloat = 10_000
    private static let expandedSeparatorLength: CGFloat = 18

    private let settings: EaveSettings

    // Rightmost visible anchor icon (minimalist Eave glyph).
    private var toggleItem: NSStatusItem!
    // Separator between Visible and Hidden sections.
    private var hiddenSeparator: NSStatusItem!
    // Optional separator between Hidden and Always-Hidden sections.
    private var alwaysHiddenSeparator: NSStatusItem?

    private var rehideTimer: Timer?
    private var appSwitchObserver: Any?

    private(set) var isHiddenExpanded: Bool = false
    private(set) var isAlwaysHiddenExpanded: Bool = false

    /// Callbacks wired by AppCoordinator for cross-module orchestration.
    var onRequestNotchBarToggle: (() -> Void)?
    var onRequestOpenSearch: (() -> Void)?
    var onRequestOpenSettings: (() -> Void)?
    var onRequestTestPeek: (() -> Void)?
    var onExpansionChanged: ((Bool, Bool) -> Void)?
    var isPointerProtectedFromRehide: (() -> Bool)?

    init(settings: EaveSettings) {
        self.settings = settings
        super.init()
        setupStatusItems()
        observeWorkspace()
    }

    func tearDown() {
        rehideTimer?.invalidate()
        rehideTimer = nil
        if let observer = appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appSwitchObserver = nil
        }
        NSStatusBar.system.removeStatusItem(toggleItem)
        NSStatusBar.system.removeStatusItem(hiddenSeparator)
        if let always = alwaysHiddenSeparator {
            NSStatusBar.system.removeStatusItem(always)
            alwaysHiddenSeparator = nil
        }
    }

    // MARK: - Public Controls

    func syncConfiguration() {
        if settings.enableAlwaysHiddenSection {
            ensureAlwaysHiddenSeparator()
        } else if let existing = alwaysHiddenSeparator {
            NSStatusBar.system.removeStatusItem(existing)
            alwaysHiddenSeparator = nil
            isAlwaysHiddenExpanded = false
        }
        applySeparatorLengths()
    }

    func toggleHidden() {
        if isHiddenExpanded {
            collapseAll()
        } else {
            expandHidden()
        }
    }

    func expandHidden(includeAlwaysHidden: Bool = false) {
        isHiddenExpanded = true
        if includeAlwaysHidden && settings.enableAlwaysHiddenSection {
            isAlwaysHiddenExpanded = true
        }
        applySeparatorLengths()
        scheduleAutoRehideIfNeeded()
        onExpansionChanged?(isHiddenExpanded, isAlwaysHiddenExpanded)
    }

    func toggleAlwaysHidden() {
        guard settings.enableAlwaysHiddenSection else {
            toggleHidden()
            return
        }
        if isAlwaysHiddenExpanded {
            isAlwaysHiddenExpanded = false
            applySeparatorLengths()
            onExpansionChanged?(isHiddenExpanded, isAlwaysHiddenExpanded)
        } else {
            expandHidden(includeAlwaysHidden: true)
        }
    }

    func collapseAll() {
        guard isHiddenExpanded || isAlwaysHiddenExpanded else { return }
        rehideTimer?.invalidate()
        rehideTimer = nil
        isHiddenExpanded = false
        isAlwaysHiddenExpanded = false
        applySeparatorLengths()
        onExpansionChanged?(false, false)
    }

    /// Resets the auto-rehide countdown (for example while the user interacts with expanded items).
    func postponeAutoRehide() {
        guard isHiddenExpanded else { return }
        scheduleAutoRehideIfNeeded()
    }

    // MARK: - Separator Coordinates (Used by Phase 3 Scanner)

    /// Screen-space X coordinate of the Hidden separator's right edge.
    var hiddenSeparatorX: CGFloat? {
        hiddenSeparator.button?.window?.frame.maxX
    }

    /// Screen-space X coordinate of the Always-Hidden separator's right edge.
    var alwaysHiddenSeparatorX: CGFloat? {
        alwaysHiddenSeparator?.button?.window?.frame.maxX
    }

    /// Window IDs owned by Eave's own control items so the scanner excludes them.
    var ownedWindowIDs: Set<CGWindowID> {
        var ids = Set<CGWindowID>()
        let windows = [
            toggleItem.button?.window,
            hiddenSeparator.button?.window,
            alwaysHiddenSeparator?.button?.window
        ]
        for window in windows {
            if let num = window?.windowNumber, num > 0, let wid = CGWindowID(exactly: num) {
                ids.insert(wid)
            }
        }
        return ids
    }

    // MARK: - Setup

    private func setupStatusItems() {
        // Seed rightmost Preferred Positions on first launch so Eave stays visible
        // beside Control Center even when the user's menu bar is already full.
        seedInitialPreferredPositionsIfNeeded()

        // Order of creation establishes sensible initial left-to-right placement:
        // [AlwaysHidden Separator] ... [Hidden Separator] ... [Toggle Anchor]
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        toggleItem.autosaveName = "eave.control.toggle"
        configureToggleButton()

        hiddenSeparator = NSStatusBar.system.statusItem(withLength: Self.collapsedSeparatorLength)
        hiddenSeparator.autosaveName = "eave.control.hidden"
        configureSeparatorButton(hiddenSeparator, symbol: "line.diagonal", tooltip: "Eave Hidden Section Divider (⌘-drag icons left to hide)")

        if settings.enableAlwaysHiddenSection {
            ensureAlwaysHiddenSeparator()
        }

        applySeparatorLengths()
    }

    private func seedInitialPreferredPositionsIfNeeded() {
        let defaults = UserDefaults.standard
        let toggleKey = "NSStatusItem Preferred Position eave.control.toggle"
        let hiddenKey = "NSStatusItem Preferred Position eave.control.hidden"
        let alwaysKey = "NSStatusItem Preferred Position eave.control.alwaysHidden"

        if defaults.object(forKey: toggleKey) == nil {
            defaults.set(0.0, forKey: toggleKey)
        }
        if defaults.object(forKey: hiddenKey) == nil {
            defaults.set(40.0, forKey: hiddenKey)
        }
        if defaults.object(forKey: alwaysKey) == nil {
            defaults.set(80.0, forKey: alwaysKey)
        }
    }

    private func ensureAlwaysHiddenSeparator() {
        guard alwaysHiddenSeparator == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: Self.collapsedSeparatorLength)
        item.autosaveName = "eave.control.alwaysHidden"
        configureSeparatorButton(item, symbol: "ellipsis", tooltip: "Eave Always-Hidden Divider (⌘-drag icons left to keep hidden)")
        alwaysHiddenSeparator = item
    }

    private func configureToggleButton() {
        guard let button = toggleItem.button else { return }
        if let icon = NSImage(named: "MenuBarIcon") {
            icon.isTemplate = true
            icon.size = NSSize(width: 18, height: 18)
            button.image = icon
        } else {
            button.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Eave")
        }
        button.imagePosition = .imageOnly
        button.toolTip = "Eave — Click to toggle hidden items, ⌥+Click for always-hidden, Right-click for menu"
        button.target = self
        button.action = #selector(handleToggleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureSeparatorButton(_ item: NSStatusItem, symbol: String, tooltip: String) {
        guard let button = item.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Eave Divider")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        button.image = image
        button.alphaValue = 0.45
        button.toolTip = tooltip
        button.appearsDisabled = false
    }

    private func applySeparatorLengths() {
        hiddenSeparator.length = isHiddenExpanded ? Self.expandedSeparatorLength : Self.collapsedSeparatorLength
        hiddenSeparator.button?.isHidden = !isHiddenExpanded

        if let always = alwaysHiddenSeparator {
            always.length = isAlwaysHiddenExpanded ? Self.expandedSeparatorLength : Self.collapsedSeparatorLength
            always.button?.isHidden = !isAlwaysHiddenExpanded
        }

        toggleItem.button?.alphaValue = isHiddenExpanded ? 1.0 : 0.85
    }

    // MARK: - Actions & Context Menu

    @objc private func handleToggleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            performPrimaryToggle()
            return
        }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            presentContextMenu(from: sender)
            return
        }

        if event.modifierFlags.contains(.option) {
            toggleAlwaysHidden()
            return
        }

        performPrimaryToggle()
    }

    private func performPrimaryToggle() {
        if settings.useNotchBarOnToggle {
            onRequestNotchBarToggle?()
        } else {
            toggleHidden()
        }
    }

    private func presentContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()

        let toggleTitle = isHiddenExpanded ? "Hide Menu Bar Items" : "Show Hidden Items"
        let toggleMenuItem = NSMenuItem(title: toggleTitle, action: #selector(menuToggleHidden), keyEquivalent: "")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        if settings.enableAlwaysHiddenSection {
            let alwaysTitle = isAlwaysHiddenExpanded ? "Hide Always-Hidden Items" : "Show Always-Hidden Items"
            let alwaysMenuItem = NSMenuItem(title: alwaysTitle, action: #selector(menuToggleAlwaysHidden), keyEquivalent: "")
            alwaysMenuItem.target = self
            menu.addItem(alwaysMenuItem)
        }

        let notchBarItem = NSMenuItem(title: "Toggle Notch Bar", action: #selector(menuToggleNotchBar), keyEquivalent: "")
        notchBarItem.target = self
        menu.addItem(notchBarItem)

        let searchItem = NSMenuItem(title: "Search Menu Bar...", action: #selector(menuOpenSearch), keyEquivalent: "")
        searchItem.target = self
        menu.addItem(searchItem)

        menu.addItem(.separator())

        let testPeekItem = NSMenuItem(title: "Send Test Notch Peek", action: #selector(menuTestPeek), keyEquivalent: "")
        testPeekItem.target = self
        menu.addItem(testPeekItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Eave", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        toggleItem.menu = menu
        button.performClick(nil)
        // Clear menu immediately so subsequent left clicks continue invoking handleToggleClick.
        toggleItem.menu = nil
    }

    @objc private func menuToggleHidden() { toggleHidden() }
    @objc private func menuToggleAlwaysHidden() { toggleAlwaysHidden() }
    @objc private func menuToggleNotchBar() { onRequestNotchBarToggle?() }
    @objc private func menuOpenSearch() { onRequestOpenSearch?() }
    @objc private func menuTestPeek() { onRequestTestPeek?() }
    @objc private func menuOpenSettings() { onRequestOpenSettings?() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: - Auto-Rehide

    private func observeWorkspace() {
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.settings.rehideOnAppSwitch, self.isHiddenExpanded else { return }
                if self.isPointerProtectedFromRehide?() == true { return }
                self.collapseAll()
            }
        }
    }

    private func scheduleAutoRehideIfNeeded() {
        rehideTimer?.invalidate()
        rehideTimer = nil
        guard settings.rehideAutomatically, settings.rehideDelaySeconds > 0 else { return }

        rehideTimer = Timer.scheduledTimer(withTimeInterval: settings.rehideDelaySeconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isHiddenExpanded else { return }
                // Pause auto-rehide while the cursor stays in the menu bar or Notch Bar.
                if self.isCursorInMenuBar() || self.isPointerProtectedFromRehide?() == true {
                    self.scheduleAutoRehideIfNeeded()
                    return
                }
                self.collapseAll()
            }
        }
    }

    private func isCursorInMenuBar() -> Bool {
        let loc = NSEvent.mouseLocation
        for screen in NSScreen.screens where screen.frame.contains(loc) {
            let barHeight = max(screen.safeAreaInsets.top, 28)
            return loc.y >= screen.frame.maxY - barHeight - 4
        }
        return false
    }
}
