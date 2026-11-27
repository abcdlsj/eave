import AppKit
import Foundation
import Observation
import SwiftUI

/// Central application coordinator assembling Menu Bar, Second Row, Notch Signals, and Quick Search subsystems.
@MainActor
@Observable
final class AppCoordinator {
    let settings: EaveSettings
    let permissions: PermissionsManager
    let launchAtLogin: LaunchAtLoginService
    let hotKeyManager: HotKeyManager

    let menuBarManager: MenuBarManager
    let eventMonitor: MenuBarEventMonitor
    let itemScanner: MenuBarItemScanner
    let clickForwarder: MenuBarClickForwarder
    let spacingManager: MenuBarSpacingManager

    let notchStateMachine: NotchStateMachine
    let signalHub: SignalHub
    let searchController: MenuBarSearchController
    let secondRowBarController: SecondRowBarController

    private var notchPanelController: NotchPanelController?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var onboardingWindowDelegate: OnboardingWindowDelegate?
    private var hiddenSyncTimer: Timer?
    private var inFlightScanTask: Task<[MenuBarItemInfo], Never>?
    private var startupFollowUpTask: Task<Void, Never>?
    private var coldSweepTask: Task<Void, Never>?
    private var workspaceRefreshDebounceTask: Task<Void, Never>?
    private var workspaceLaunchObserver: Any?
    private var workspaceTerminateObserver: Any?

    private(set) var discoveredItems: [MenuBarItemInfo] = []
    private(set) var isScanningBarItems: Bool = false
    private var lastScannedSignature: [String] = []
    private var lastMenuBarScanTime: CFAbsoluteTime = 0

    init() {
        let settings = EaveSettings()
        self.settings = settings
        self.permissions = PermissionsManager()
        self.launchAtLogin = LaunchAtLoginService()
        self.hotKeyManager = HotKeyManager()

        let menuBarManager = MenuBarManager(settings: settings)
        self.menuBarManager = menuBarManager
        self.eventMonitor = MenuBarEventMonitor(settings: settings)
        let scanner = MenuBarItemScanner()
        self.itemScanner = scanner
        self.clickForwarder = MenuBarClickForwarder(menuBarManager: menuBarManager, scanner: scanner)
        self.spacingManager = MenuBarSpacingManager()

        let stateMachine = NotchStateMachine()
        self.notchStateMachine = stateMachine
        self.signalHub = SignalHub(settings: settings, stateMachine: stateMachine)
        self.searchController = MenuBarSearchController()
        self.secondRowBarController = SecondRowBarController()
    }

    func start() {
        applyAppearance()
        setupNotchPanel()
        wireMenuBarCallbacks()
        wireSecondRowBar()
        wireEventMonitor()
        wireHotKeys()
        wireSearch()

        permissions.onAccessibilityChanged = { [weak self] granted in
            self?.handleAccessibilityChanged(granted: granted)
        }
        permissions.startPolling(interval: 8.0)
        observeAppReactivation()
        eventMonitor.start()
        signalHub.start()
        startHiddenDiscoverySync()

        if !settings.hasCompletedOnboarding {
            DispatchQueue.main.async { [weak self] in
                self?.openOnboardingWindow()
            }
        }
    }

    func applyAppearance() {
        let mode = settings.appearanceMode
        let appearance = mode.nsAppearance
        NSApp.appearance = appearance
        settingsWindow?.appearance = appearance
        onboardingWindow?.appearance = appearance
        secondRowBarController.applyAppearance(mode)
        searchController.applyAppearance(mode)
    }

    func stop() {
        hiddenSyncTimer?.invalidate()
        hiddenSyncTimer = nil
        inFlightScanTask?.cancel()
        inFlightScanTask = nil
        startupFollowUpTask?.cancel()
        startupFollowUpTask = nil
        coldSweepTask?.cancel()
        coldSweepTask = nil
        workspaceRefreshDebounceTask?.cancel()
        workspaceRefreshDebounceTask = nil
        if let observer = workspaceLaunchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceLaunchObserver = nil
        }
        if let observer = workspaceTerminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceTerminateObserver = nil
        }
        if let observer = appReactivationObserver {
            NotificationCenter.default.removeObserver(observer)
            appReactivationObserver = nil
        }
        permissions.stopPolling()
        eventMonitor.stop()
        signalHub.stop()
        hotKeyManager.tearDown()
        secondRowBarController.tearDown()
        notchPanelController?.tearDown()
        menuBarManager.tearDown()
    }

    // MARK: - High-Level Actions

    func showSecondRowBar(anchorFrame: CGRect? = nil, pinnedForPreview: Bool = false) {
        let resolvedAnchor = anchorFrame ?? menuBarManager.toggleItemFrame(near: NSEvent.mouseLocation)
        let hasFreshCache = !discoveredItems.isEmpty && (CFAbsoluteTimeGetCurrent() - lastMenuBarScanTime) < 6.0
        secondRowBarController.show(
            anchorFrame: resolvedAnchor,
            items: secondRowHiddenItems,
            activeBadges: signalHub.activeBadgesByBundleID,
            itemsPerRow: settings.secondRowItemsPerRow,
            layoutMode: settings.secondRowLayoutMode,
            isScanning: !hasFreshCache && discoveredItems.isEmpty,
            needsAccessibilityPermission: !permissions.hasAccessibility,
            pinnedForPreview: pinnedForPreview
        )
        if !hasFreshCache {
            Task {
                await refreshMenuBarItems()
            }
        }
    }

    func syncHoverSettings() {
        if !settings.expandOnEaveHover {
            eventMonitor.cancelPendingHover()
            secondRowBarController.hide()
            return
        }
        if settings.hoverDisplayMode != .secondRow {
            secondRowBarController.hide()
            return
        }
        if secondRowBarController.isVisible {
            secondRowBarController.updateContent(
                items: secondRowHiddenItems,
                activeBadges: signalHub.activeBadgesByBundleID,
                itemsPerRow: settings.secondRowItemsPerRow,
                layoutMode: settings.secondRowLayoutMode,
                isScanning: isScanningBarItems,
                needsAccessibilityPermission: !permissions.hasAccessibility,
                anchorFrame: nil
            )
        }
    }

    func openSearch() {
        secondRowBarController.hide()
        searchController.open(initialItems: discoveredItems)
    }

    func openOnboardingWindow() {
        if onboardingWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 484),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Welcome to Eave"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.appearance = settings.appearanceMode.nsAppearance
            window.center()

            let delegate = OnboardingWindowDelegate { [weak self] in
                self?.handleOnboardingClosed()
            }
            window.delegate = delegate
            onboardingWindowDelegate = delegate
            onboardingWindow = window
        }

        if let window = onboardingWindow {
            window.appearance = settings.appearanceMode.nsAppearance
            window.contentView = NSHostingView(
                rootView: OnboardingView(coordinator: self) { [weak self] in
                    self?.completeOnboardingAndClose()
                }
            )
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func completeOnboardingAndClose() {
        settings.hasCompletedOnboarding = true
        if menuBarManager.isHiddenExpanded {
            menuBarManager.collapseAll()
        }
        onboardingWindow?.close()
    }

    private func handleOnboardingClosed() {
        settings.hasCompletedOnboarding = true
        permissions.startPolling(interval: 8.0)
        Task {
            await refreshMenuBarItems()
        }
    }

    func openSettingsWindow() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Eave Settings"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.appearance = settings.appearanceMode.nsAppearance
            window.center()
            window.contentView = NSHostingView(rootView: SettingsView(coordinator: self))
            settingsWindow = window
        } else {
            settingsWindow?.appearance = settings.appearanceMode.nsAppearance
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "eave" {
            switch url.host?.lowercased() {
            case "settings":
                openSettingsWindow()
                return true
            case "onboarding":
                openOnboardingWindow()
                return true
            case "search":
                openSearch()
                return true
            default:
                break
            }
        }
        return signalHub.bridge.handleIncomingURL(url)
    }

    @discardableResult
    func refreshMenuBarItems() async -> [MenuBarItemInfo] {
        // Coalesce concurrent scan requests so startup, hover, and Search never compete for AX/CGWindowList IPC.
        if let existing = inFlightScanTask {
            return await existing.value
        }

        let task = Task { @MainActor [weak self] () -> [MenuBarItemInfo] in
            guard let self else { return [] }
            self.isScanningBarItems = true
            defer {
                self.isScanningBarItems = false
                self.inFlightScanTask = nil
            }

            let scanned = await self.itemScanner.scanAsync(
                hiddenSeparatorX: self.menuBarManager.hiddenSeparatorX,
                excludingWindowIDs: self.menuBarManager.ownedWindowIDs
            )
            self.lastMenuBarScanTime = CFAbsoluteTimeGetCurrent()
            self.syncHiddenBundleIDs(from: scanned)

            let signature = scanned.map { "\($0.id)|\($0.section.rawValue)|\($0.title)" }
            let changed = signature != self.lastScannedSignature || self.discoveredItems.isEmpty
            self.lastScannedSignature = signature

            if changed {
                AppIconService.shared.prewarmAsync(items: scanned)
                self.discoveredItems = scanned
            }

            if self.secondRowBarController.isVisible && (changed || self.secondRowBarController.isScanning) {
                self.secondRowBarController.updateContent(
                    items: self.secondRowHiddenItems,
                    activeBadges: self.signalHub.activeBadgesByBundleID,
                    itemsPerRow: self.settings.secondRowItemsPerRow,
                    layoutMode: self.settings.secondRowLayoutMode,
                    isScanning: false,
                    needsAccessibilityPermission: !self.permissions.hasAccessibility,
                    anchorFrame: nil
                )
            }
            return self.discoveredItems
        }

        inFlightScanTask = task
        return await task.value
    }

    private var secondRowHiddenItems: [MenuBarItemInfo] {
        discoveredItems.filter { $0.section == .hidden }
    }

    // MARK: - Private Wiring

    private func setupNotchPanel() {
        let controller = NotchPanelController(stateMachine: notchStateMachine) { [unowned self] in
            NotchContainerView(
                stateMachine: self.notchStateMachine,
                geometryProvider: { self.notchPanelController?.geometry ?? NotchGeometryResolver.currentGeometry() },
                onAlertAction: { alert in
                    self.signalHub.performPrimaryAction(for: alert)
                    self.notchPanelController?.updateMouseInteractivity()
                },
                onAmbientAction: { indicator in
                    self.signalHub.performAction(for: indicator)
                }
            )
        }
        notchPanelController = controller
    }

    private func wireMenuBarCallbacks() {
        menuBarManager.onRequestOpenSearch = { [weak self] in
            self?.openSearch()
        }
        menuBarManager.onRequestOpenSettings = { [weak self] in
            self?.openSettingsWindow()
        }
        menuBarManager.onRequestOpenOnboarding = { [weak self] in
            self?.openOnboardingWindow()
        }
        menuBarManager.onToggleHoverChanged = { [weak self] isHovering in
            self?.eventMonitor.handleEaveToggleHover(isHovering: isHovering)
        }
        menuBarManager.onWillHandleToggleInteraction = { [weak self] in
            guard let self else { return }
            // Keep the pointer that is resting on the icon from re-triggering hover reveal right after the click.
            self.eventMonitor.suppressHoverUntilPointerExits()
            // Dismiss any visible Second Row immediately so a left-click expands inline (and a
            // right-click opens the context menu) without waiting for the hover card to fade out.
            if self.secondRowBarController.isVisible {
                self.secondRowBarController.hide()
            }
        }
        menuBarManager.isAutoRehidePaused = { [weak self] in
            // Onboarding teaches ⌘-dragging around the divider; don't collapse it mid-lesson.
            self?.onboardingWindow?.isVisible == true
        }
        menuBarManager.isPointerProtectedFromRehide = { [weak self] in
            guard let self else { return false }
            let loc = NSEvent.mouseLocation
            return self.secondRowBarController.isVisible
                || (self.notchPanelController?.isPointInsideActiveSurface(loc) ?? false)
        }
    }

    private func wireSecondRowBar() {
        secondRowBarController.onSelectItem = { [weak self] item, button in
            guard let self else { return }
            Task {
                await self.clickForwarder.trigger(
                    item,
                    button: button,
                    preferAppActivationForRegularApps: true
                )
            }
        }
        secondRowBarController.onRequestPermissions = { [weak self] in
            self?.permissions.requestAccessibilityPrompt()
            self?.permissions.openAccessibilitySettings()
        }
        secondRowBarController.shouldDismissOnAppSwitch = { [weak self] in
            self?.settings.rehideAutomatically ?? true
        }
        secondRowBarController.onRequestShowDivider = { [weak self] in
            self?.secondRowBarController.hide()
            self?.menuBarManager.expandHidden()
        }
    }

    private func wireEventMonitor() {
        eventMonitor.toggleItemFramesProvider = { [weak self] in
            self?.menuBarManager.allToggleItemFrames ?? []
        }
        eventMonitor.isHoverSuppressed = { [weak self] in
            guard let self else { return true }
            return self.menuBarManager.isContextMenuOpen
                || self.searchController.isVisible
        }
        eventMonitor.onHoverExpand = { [weak self] anchorFrame in
            guard let self else { return }
            switch self.settings.hoverDisplayMode {
            case .inline:
                guard !self.menuBarManager.isHiddenExpanded else { return }
                self.menuBarManager.expandHiddenFromHover()
            case .secondRow:
                guard !self.menuBarManager.isHiddenExpanded else { return }
                guard !self.secondRowBarController.isVisible else { return }
                self.showSecondRowBar(anchorFrame: anchorFrame, pinnedForPreview: false)
            }
        }
        eventMonitor.onOutsideClick = { [weak self] in
            guard let self else { return }
            let loc = NSEvent.mouseLocation
            if self.secondRowBarController.isVisible,
               !self.secondRowBarController.isPointInsideCard(loc) {
                self.secondRowBarController.hide()
            }
            if self.menuBarManager.isHiddenExpanded,
               self.notchPanelController?.isPointInsideActiveSurface(loc) == false,
               !self.menuBarManager.transientTargetHasOpenUI(),
               self.onboardingWindow?.isVisible != true {
                if self.menuBarManager.isPointInMenuBarPopoverOrMenu(loc) {
                    self.menuBarManager.postponeAutoRehide()
                } else if self.menuBarManager.isTransientForwardExpansion || self.settings.rehideAutomatically {
                    self.menuBarManager.collapseAll()
                }
            }
            if self.searchController.isVisible {
                self.searchController.close()
            }
        }
        eventMonitor.onMouseMoved = { [weak self] point in
            guard let self else { return }
            self.notchPanelController?.handleGlobalPointerMove(to: point)
            self.secondRowBarController.handleGlobalPointerMove(
                to: point,
                anchorFrame: self.menuBarManager.toggleItemFrame(near: point)
            )
        }
        eventMonitor.needsPointerTracking = { [weak self] in
            guard let self else { return false }
            return self.notchStateMachine.isInteractiveState || self.secondRowBarController.isVisible
        }
    }

    enum HotKeyUpdateError: Error, Equatable {
        case missingModifier
        case duplicate(HotKeyAction)
        case unavailable
    }

    /// Validates, registers, and persists a new shortcut. On failure the previous binding is restored
    /// and the reason is returned so the UI can explain it instead of silently showing a dead combo.
    @discardableResult
    func updateHotKey(_ combo: KeyCombo?, for action: HotKeyAction) -> HotKeyUpdateError? {
        let previous = settings.hotKey(for: action)
        if let combo {
            guard combo.isValidGlobalHotKey else { return .missingModifier }
            if let other = HotKeyAction.allCases.first(where: { $0 != action && settings.hotKey(for: $0) == combo }) {
                return .duplicate(other)
            }
            guard hotKeyManager.register(action: action, combo: combo) else {
                hotKeyManager.register(action: action, combo: previous)
                return .unavailable
            }
        } else {
            hotKeyManager.register(action: action, combo: nil)
        }
        settings.setHotKey(combo, for: action)
        return nil
    }

    /// Call while a shortcut recorder is capturing keys; pass false to restore the saved shortcuts.
    func setHotKeysSuspended(_ suspended: Bool) {
        if suspended {
            hotKeyManager.suspendAll()
        } else {
            hotKeyManager.register(settings: settings)
        }
    }

    private func wireHotKeys() {
        hotKeyManager.register(settings: settings)
        hotKeyManager.onTrigger = { [weak self] action in
            guard let self else { return }
            switch action {
            case .toggleHidden:
                self.menuBarManager.toggleHidden()
            case .openSearch:
                self.openSearch()
            }
        }
    }

    private func wireSearch() {
        searchController.onRequestRefreshItems = { [weak self] in
            guard let self else { return [] }
            return await self.refreshMenuBarItems()
        }
        searchController.onSelectItem = { [weak self] item in
            guard let self else { return }
            Task {
                await self.clickForwarder.trigger(
                    item,
                    button: .left,
                    preferAppActivationForRegularApps: true
                )
            }
        }
    }

    private func startHiddenDiscoverySync() {
        // Phase 1: Immediate fast scan (<60ms) using WindowServer layer-25 proxies + known/accessory AX apps.
        Task { [weak self] in
            await self?.refreshMenuBarItems()
        }

        // Follow-up once WindowServer finishes placing Eave's freshly created hidden separator on launch.
        startupFollowUpTask?.cancel()
        startupFollowUpTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled else { return }
            self.menuBarManager.refreshToggleFramesCache()
            if !self.itemScanner.lastScanLocatedSeparatorBand || self.discoveredItems.isEmpty {
                await self.refreshMenuBarItems()
            }
        }

        // Phase 2: Quiet low-priority background sweep over remaining regular apps so newly installed
        // regular apps with status items are discovered without ever slowing down cold launch.
        coldSweepTask?.cancel()
        coldSweepTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard let self, !Task.isCancelled else { return }
            let foundNew = await self.itemScanner.sweepUnscannedRegularAppsAsync()
            if foundNew && !Task.isCancelled {
                await self.refreshMenuBarItems()
            }
        }

        observeWorkspaceAppChanges()

        // Background safety-net rescan. App launch/quit, hover, and Search already trigger fresh scans,
        // so this only needs to catch silent changes; skip it when a recent scan is still fresh.
        hiddenSyncTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard CFAbsoluteTimeGetCurrent() - self.lastMenuBarScanTime > 12.0 else { return }
                await self.refreshMenuBarItems()
            }
        }
    }

    private var appReactivationObserver: Any?

    /// Users grant Accessibility in System Settings and then come back; re-check right away instead of
    /// waiting for the next 8s poll.
    private func observeAppReactivation() {
        appReactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.permissions.refresh()
            }
        }
    }

    private func handleAccessibilityChanged(granted: Bool) {
        guard granted else { return }
        // The startup cold sweep bails out without permission, so run it now that AX works.
        coldSweepTask?.cancel()
        coldSweepTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshMenuBarItems()
            let foundNew = await self.itemScanner.sweepUnscannedRegularAppsAsync()
            if foundNew && !Task.isCancelled {
                await self.refreshMenuBarItems()
            }
        }
    }

    private func observeWorkspaceAppChanges() {
        let nc = NSWorkspace.shared.notificationCenter
        workspaceLaunchObserver = nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleWorkspaceMenuBarRefresh()
            }
        }
        workspaceTerminateObserver = nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleWorkspaceMenuBarRefresh()
            }
        }
    }

    private func scheduleWorkspaceMenuBarRefresh() {
        workspaceRefreshDebounceTask?.cancel()
        workspaceRefreshDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.refreshMenuBarItems()
        }
    }

    private func syncHiddenBundleIDs(from items: [MenuBarItemInfo]) {
        let hiddenIDs = Set(
            items
                .filter { $0.section == .hidden }
                .compactMap(\.bundleIdentifier)
        )
        signalHub.updateDiscoveredHiddenBundleIDs(hiddenIDs)
    }
}

@MainActor
private final class OnboardingWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
