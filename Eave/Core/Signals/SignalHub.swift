import AppKit
import Foundation

/// Aggregates signals from DockBadgeMonitor, MenuBarAXWatcher, and NotchBridge,
/// routing filtered notifications into the NotchStateMachine.
@MainActor
final class SignalHub {
    private let settings: EaveSettings
    private let stateMachine: NotchStateMachine
    private let dockMonitor = DockBadgeMonitor()
    private let menuBarAXWatcher = MenuBarAXWatcher()
    let bridge = NotchBridge()

    /// Bundle IDs automatically discovered in Eave's hidden menu bar section.
    private(set) var discoveredHiddenBundleIDs: Set<String> = []
    /// Live Dock unread badge labels keyed by bundle identifier (used to decorate Second Row icons).
    private(set) var activeBadgesByBundleID: [String: String] = [:]

    init(settings: EaveSettings, stateMachine: NotchStateMachine) {
        self.settings = settings
        self.stateMachine = stateMachine
        wireSources()
    }

    func start() {
        dockMonitor.start(interval: 2.0)
        if settings.enableNotchPeek {
            menuBarAXWatcher.start(interval: 4.0)
        }
        bridge.start()
    }

    func stop() {
        dockMonitor.stop()
        menuBarAXWatcher.stop()
        bridge.stop()
    }

    func syncSettings() {
        if settings.enableNotchPeek {
            menuBarAXWatcher.start(interval: 4.0)
        } else {
            menuBarAXWatcher.stop()
            stateMachine.dismissPeek()
            stateMachine.clearAllAmbient()
        }
    }

    func updateDiscoveredHiddenBundleIDs(_ bundleIDs: Set<String>) {
        discoveredHiddenBundleIDs = bundleIDs
    }

    /// Returns the combined set of bundle IDs monitored for Notch notifications.
    func effectiveWatchedBundleIDs() -> Set<String> {
        var result = Set(settings.watchedBundleIDs)
        if settings.watchHiddenAppsAutomatically {
            result.formUnion(discoveredHiddenBundleIDs)
        }
        // Never watch Eave itself.
        if let ownID = Bundle.main.bundleIdentifier {
            result.remove(ownID)
        }
        return result
    }

    func sendTestPeek() {
        let alert = NotchAlert(
            source: .system,
            title: "Eave",
            subtitle: "Hidden app notifications appear right here",
            badge: "3",
            symbolName: "bell.fill",
            accentHex: nil,
            duration: settings.peekDurationSeconds
        )
        stateMachine.presentPeek(alert)
    }

    func performPrimaryAction(for alert: NotchAlert) {
        stateMachine.dismissPeek()
        if let url = alert.targetURL {
            NSWorkspace.shared.open(url)
            return
        }
        if let bundleID = alert.bundleIdentifier {
            activateApplication(bundleIdentifier: bundleID)
        }
    }

    func performAction(for indicator: AmbientIndicator) {
        if let url = indicator.targetURL {
            NSWorkspace.shared.open(url)
            return
        }
        if let bundleID = indicator.bundleIdentifier {
            activateApplication(bundleIdentifier: bundleID)
        }
    }

    // MARK: - Wiring

    private func wireSources() {
        dockMonitor.watchedBundleIDsProvider = { [weak self] in
            self?.effectiveWatchedBundleIDs() ?? []
        }

        dockMonitor.onBadgesChanged = { [weak self] diff, current in
            self?.handleDockDiff(diff, currentSnapshots: current)
        }

        menuBarAXWatcher.watchedBundleIDsProvider = { [weak self] in
            self?.effectiveWatchedBundleIDs() ?? []
        }

        menuBarAXWatcher.onStatusTextChanged = { [weak self] bundleID, appName, statusText in
            self?.handleMenuBarAXChange(bundleID: bundleID, appName: appName, statusText: statusText)
        }

        bridge.onPayloadReceived = { [weak self] payload in
            self?.handleBridgePayload(payload)
        }
    }

    private func handleDockDiff(
        _ diff: DockBadgeDiffEngine.DiffResult,
        currentSnapshots: [String: DockBadgeSnapshot]
    ) {
        activeBadgesByBundleID = currentSnapshots.mapValues(\.badge)

        for clearedID in diff.clearedBundleIDs {
            stateMachine.removeAmbient(id: "dock.\(clearedID)")
        }

        guard settings.enableNotchPeek else { return }

        let watched = effectiveWatchedBundleIDs()
        for (bundleID, snap) in currentSnapshots where watched.contains(bundleID) {
            stateMachine.upsertAmbient(
                AmbientIndicator(
                    id: "dock.\(bundleID)",
                    source: .dockBadge,
                    title: snap.appName,
                    badge: snap.badge,
                    symbolName: nil,
                    accentHex: "#EF4444",
                    bundleIdentifier: bundleID,
                    targetURL: nil
                )
            )
        }

        guard let latest = diff.newlyTriggered.last else { return }
        let alert = NotchAlert(
            id: "dock.\(latest.bundleIdentifier).\(latest.badge)",
            source: .dockBadge,
            title: latest.appName,
            subtitle: "New notification badge",
            badge: latest.badge,
            symbolName: nil,
            accentHex: "#EF4444",
            bundleIdentifier: latest.bundleIdentifier,
            duration: settings.peekDurationSeconds
        )
        stateMachine.presentPeek(alert)
    }

    private func handleMenuBarAXChange(bundleID: String, appName: String, statusText: String) {
        guard settings.enableNotchPeek else { return }
        let alert = NotchAlert(
            id: "ax.\(bundleID)",
            source: .menuBarAX,
            title: appName,
            subtitle: statusText,
            badge: nil,
            symbolName: "menubar.rectangle",
            accentHex: "#60A5FA",
            bundleIdentifier: bundleID,
            duration: settings.peekDurationSeconds
        )
        stateMachine.presentPeek(alert)
    }

    private func handleBridgePayload(_ payload: BridgePayload) {
        guard settings.enableNotchBridge else { return }
        let key = "bridge.\(payload.id)"

        switch payload.mode {
        case .clear:
            stateMachine.removeAmbient(id: key)
            stateMachine.dismissPeek()
        case .ambient:
            guard settings.enableNotchPeek else { return }
            stateMachine.upsertAmbient(
                AmbientIndicator(
                    id: key,
                    source: .bridge,
                    title: payload.title,
                    badge: payload.badge,
                    symbolName: payload.symbolName ?? "sparkle",
                    accentHex: payload.accentHex ?? "#38BDF8",
                    bundleIdentifier: payload.bundleIdentifier,
                    targetURL: payload.targetURL
                )
            )
        case .peek:
            guard settings.enableNotchPeek else { return }
            let alert = NotchAlert(
                id: key,
                source: .bridge,
                title: payload.title,
                subtitle: payload.subtitle,
                badge: payload.badge,
                symbolName: payload.symbolName ?? "bolt.fill",
                accentHex: payload.accentHex ?? "#38BDF8",
                bundleIdentifier: payload.bundleIdentifier,
                targetURL: payload.targetURL,
                duration: payload.duration
            )
            stateMachine.presentPeek(alert)
        }
    }

    private func activateApplication(bundleIdentifier: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
           let bundleURL = app.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in }
            return
        }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            app.activate(options: [.activateAllWindows])
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
