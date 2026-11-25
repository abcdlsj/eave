import AppKit
import Foundation
import Observation
import SwiftUI

/// Central application coordinator assembling Phase 1, Phase 2, and Phase 3 subsystems.
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
    let imageCapturer: MenuBarImageCapturer
    let clickForwarder: MenuBarClickForwarder
    let spacingManager: MenuBarSpacingManager

    let notchStateMachine: NotchStateMachine
    let signalHub: SignalHub
    let searchController: MenuBarSearchController

    private var notchPanelController: NotchPanelController?
    private var settingsWindow: NSWindow?
    private var hiddenSyncTimer: Timer?

    private(set) var capturedItems: [CapturedMenuBarItem] = []
    private(set) var isScanningBarItems: Bool = false
    private var lastScannedSignature: [String] = []

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
        self.imageCapturer = MenuBarImageCapturer()
        self.clickForwarder = MenuBarClickForwarder(menuBarManager: menuBarManager, scanner: scanner)
        self.spacingManager = MenuBarSpacingManager()

        let stateMachine = NotchStateMachine()
        self.notchStateMachine = stateMachine
        self.signalHub = SignalHub(settings: settings, stateMachine: stateMachine)
        self.searchController = MenuBarSearchController()
    }

    func start() {
        setupNotchPanel()
        wireMenuBarCallbacks()
        wireEventMonitor()
        wireHotKeys()
        wireSearch()

        permissions.startPolling(interval: 8.0)
        eventMonitor.start()
        signalHub.start()
        startHiddenDiscoverySync()
    }

    func stop() {
        hiddenSyncTimer?.invalidate()
        hiddenSyncTimer = nil
        permissions.stopPolling()
        eventMonitor.stop()
        signalHub.stop()
        hotKeyManager.tearDown()
        notchPanelController?.tearDown()
        menuBarManager.tearDown()
    }

    // MARK: - High-Level Actions

    func toggleNotchBar() {
        if notchStateMachine.isBarOpen {
            notchStateMachine.closeBar()
            notchPanelController?.updateMouseInteractivity()
        } else {
            notchStateMachine.openBar()
            notchPanelController?.updateMouseInteractivity()
            Task {
                await refreshCapturedMenuBarItems()
            }
        }
    }

    func openSearch() {
        if notchStateMachine.isBarOpen {
            notchStateMachine.closeBar()
        }
        searchController.open()
    }

    func openSettingsWindow() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Eave Settings"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(rootView: SettingsView(coordinator: self))
            settingsWindow = window
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
            case "bar":
                toggleNotchBar()
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
    func refreshCapturedMenuBarItems() async -> [CapturedMenuBarItem] {
        isScanningBarItems = true
        defer { isScanningBarItems = false }

        let scanned = await itemScanner.scanAsync(
            hiddenSeparatorX: menuBarManager.hiddenSeparatorX,
            alwaysHiddenSeparatorX: menuBarManager.alwaysHiddenSeparatorX,
            excludingWindowIDs: menuBarManager.ownedWindowIDs
        )
        syncHiddenBundleIDs(from: scanned)

        let captured = await imageCapturer.captureItems(
            scanned,
            allowLiveCapture: settings.enableLiveIconCapture
        )
        capturedItems = captured
        return captured
    }

    // MARK: - Private Wiring

    private func setupNotchPanel() {
        let controller = NotchPanelController(stateMachine: notchStateMachine) { [unowned self] in
            NotchContainerView(
                stateMachine: self.notchStateMachine,
                geometryProvider: { self.notchPanelController?.geometry ?? NotchGeometryResolver.currentGeometry() },
                capturedItemsProvider: { self.capturedItems },
                activeBadgesProvider: { self.signalHub.activeBadgesByBundleID },
                isScanningProvider: { self.isScanningBarItems },
                onSelectBarItem: { item in
                    self.notchStateMachine.closeBar()
                    self.notchPanelController?.updateMouseInteractivity()
                    Task {
                        await self.clickForwarder.trigger(item)
                    }
                },
                onRefreshBar: {
                    Task {
                        await self.refreshCapturedMenuBarItems()
                    }
                },
                onOpenSearch: {
                    self.openSearch()
                },
                onOpenSettings: {
                    self.notchStateMachine.closeBar()
                    self.notchPanelController?.updateMouseInteractivity()
                    self.openSettingsWindow()
                },
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
        menuBarManager.onRequestNotchBarToggle = { [weak self] in
            self?.toggleNotchBar()
        }
        menuBarManager.onRequestOpenSearch = { [weak self] in
            self?.openSearch()
        }
        menuBarManager.onRequestOpenSettings = { [weak self] in
            self?.openSettingsWindow()
        }
        menuBarManager.onRequestTestPeek = { [weak self] in
            self?.signalHub.sendTestPeek()
            self?.notchPanelController?.updateMouseInteractivity()
        }
        menuBarManager.isPointerProtectedFromRehide = { [weak self] in
            guard let self else { return false }
            let loc = NSEvent.mouseLocation
            return self.notchStateMachine.isBarOpen
                || (self.notchPanelController?.isPointInsideActiveSurface(loc) ?? false)
        }
    }

    private func wireEventMonitor() {
        eventMonitor.onScrollExpand = { [weak self] in
            guard let self else { return }
            if self.settings.useNotchBarOnToggle {
                if !self.notchStateMachine.isBarOpen { self.toggleNotchBar() }
            } else {
                self.menuBarManager.expandHidden()
            }
        }
        eventMonitor.onScrollCollapse = { [weak self] in
            guard let self else { return }
            let loc = NSEvent.mouseLocation
            // Do not hijack horizontal/vertical scrolling while the user is scrolling inside Notch Bar.
            if self.notchStateMachine.isBarOpen,
               self.notchPanelController?.isPointInsideActiveSurface(loc) == true {
                return
            }
            if self.notchStateMachine.isBarOpen {
                self.notchStateMachine.closeBar()
            }
            self.menuBarManager.collapseAll()
        }
        eventMonitor.onHoverExpand = { [weak self] in
            guard let self, !self.menuBarManager.isHiddenExpanded else { return }
            self.menuBarManager.expandHidden()
        }
        eventMonitor.onOutsideClick = { [weak self] in
            guard let self else { return }
            let loc = NSEvent.mouseLocation
            if self.notchStateMachine.isBarOpen,
               self.notchPanelController?.isPointInsideActiveSurface(loc) == false {
                self.notchStateMachine.closeBar()
                self.notchPanelController?.updateMouseInteractivity()
            }
            if self.menuBarManager.isHiddenExpanded,
               self.notchPanelController?.isPointInsideActiveSurface(loc) == false {
                self.menuBarManager.collapseAll()
            }
            if self.searchController.isVisible {
                self.searchController.close()
            }
        }
        eventMonitor.onMouseMoved = { [weak self] point in
            self?.notchPanelController?.handleGlobalPointerMove(to: point)
        }
        eventMonitor.needsPointerTracking = { [weak self] in
            self?.notchStateMachine.isInteractiveState ?? false
        }
    }

    private func wireHotKeys() {
        hotKeyManager.register(settings: settings)
        hotKeyManager.onTrigger = { [weak self] action in
            guard let self else { return }
            switch action {
            case .toggleHidden:
                self.menuBarManager.toggleHidden()
            case .toggleNotchBar:
                self.toggleNotchBar()
            case .openSearch:
                self.openSearch()
            }
        }
    }

    private func wireSearch() {
        searchController.onRequestRefreshItems = { [weak self] in
            guard let self else { return [] }
            return await self.refreshCapturedMenuBarItems()
        }
        searchController.onSelectItem = { [weak self] item in
            guard let self else { return }
            Task {
                await self.clickForwarder.trigger(item)
            }
        }
    }

    private func startHiddenDiscoverySync() {
        performLightweightHiddenScan()
        hiddenSyncTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performLightweightHiddenScan()
            }
        }
    }

    private func performLightweightHiddenScan() {
        // Never disrupt active Notch Bar scrolling/hovering with background cache replacements.
        guard !notchStateMachine.isBarOpen else { return }
        let hiddenX = menuBarManager.hiddenSeparatorX
        let alwaysX = menuBarManager.alwaysHiddenSeparatorX
        let owned = menuBarManager.ownedWindowIDs
        Task { [weak self] in
            guard let self else { return }
            let scanned = await self.itemScanner.scanAsync(
                hiddenSeparatorX: hiddenX,
                alwaysHiddenSeparatorX: alwaysX,
                excludingWindowIDs: owned
            )
            self.syncHiddenBundleIDs(from: scanned)

            let signature = scanned.map { "\($0.id)|\($0.section.rawValue)|\($0.title)" }
            guard signature != self.lastScannedSignature else { return }
            self.lastScannedSignature = signature

            if !self.isScanningBarItems && !self.notchStateMachine.isBarOpen {
                self.capturedItems = await self.imageCapturer.captureItems(
                    scanned,
                    allowLiveCapture: self.settings.enableLiveIconCapture
                )
            }
        }
    }

    private func syncHiddenBundleIDs(from items: [MenuBarItemInfo]) {
        let hiddenIDs = Set(
            items
                .filter { $0.section != .visible }
                .compactMap(\.bundleIdentifier)
        )
        signalHub.updateDiscoveredHiddenBundleIDs(hiddenIDs)
    }
}
