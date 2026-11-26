import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Pure section classifier & fuzzy search engine (isolated for deterministic unit tests).
enum MenuBarSearchEngine {
    /// Classifies an item's X coordinate relative to Eave's hidden separator position.
    static func classifySection(
        itemMidX: CGFloat,
        hiddenSeparatorX: CGFloat?
    ) -> MenuBarSection {
        if let hiddenX = hiddenSeparatorX, itemMidX < hiddenX {
            return .hidden
        }
        return .visible
    }

    /// Fuzzy-filters and ranks menu bar items by query (prefix > word-boundary > substring > subsequence).
    static func filter(items: [MenuBarItemInfo], query: String) -> [MenuBarItemInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return items.sorted { lhs, rhs in
                if lhs.section != rhs.section {
                    return sectionRank(lhs.section) < sectionRank(rhs.section)
                }
                return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
            }
        }

        let needle = trimmed.lowercased()
        let scored: [(item: MenuBarItemInfo, score: Int)] = items.compactMap { item in
            guard let score = matchScore(text: item.searchableText.lowercased(), needle: needle) else {
                return nil
            }
            return (item, score)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.item.appName.localizedCaseInsensitiveCompare(rhs.item.appName) == .orderedAscending
            }
            .map(\.item)
    }

    private static func sectionRank(_ section: MenuBarSection) -> Int {
        switch section {
        case .hidden: 0
        case .visible: 1
        }
    }

    static func matchScore(text: String, needle: String) -> Int? {
        if text == needle { return 1000 }
        if text.hasPrefix(needle) { return 800 }
        if let range = text.range(of: needle) {
            let offset = text.distance(from: text.startIndex, to: range.lowerBound)
            let isWordStart = offset == 0 || text[text.index(before: range.lowerBound)] == " "
            return (isWordStart ? 650 : 500) - min(offset, 200)
        }

        // Subsequence fuzzy match (e.g. "wc" -> "WeChat").
        var textIdx = text.startIndex
        var score = 200
        var consecutive = 0
        for ch in needle {
            guard let found = text[textIdx...].firstIndex(of: ch) else {
                return nil
            }
            if found == textIdx {
                consecutive += 1
                score += 20 * consecutive
            } else {
                consecutive = 0
                score -= 2
            }
            textIdx = text.index(after: found)
        }
        return max(score, 10)
    }

    /// Returns 0-based character offsets in `text` that match `query` (exact substring first, then subsequence),
    /// enabling crisp Raycast-style match highlighting in the search palette.
    static func matchedIndices(in text: String, query: String) -> Set<Int> {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }

        let chars = Array(text.lowercased())
        let needleChars = Array(needle)
        guard !chars.isEmpty, needleChars.count <= chars.count else { return [] }

        // Prefer contiguous substring match so highlights stay visually tight.
        if let start = contiguousRangeStart(in: chars, needle: needleChars) {
            return Set(start..<(start + needleChars.count))
        }

        // Fall back to subsequence match offsets.
        var result = Set<Int>()
        var searchFrom = 0
        for target in needleChars {
            guard let found = chars[searchFrom...].firstIndex(of: target) else {
                return []
            }
            result.insert(found)
            searchFrom = found + 1
        }
        return result
    }

    private static func contiguousRangeStart(in haystack: [Character], needle: [Character]) -> Int? {
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
        let limit = haystack.count - needle.count
        for start in 0...limit {
            var matched = true
            for offset in 0..<needle.count {
                if haystack[start + offset] != needle[offset] {
                    matched = false
                    break
                }
            }
            if matched { return start }
        }
        return nil
    }
}

/// Dual-track menu bar scanner:
/// 1. Window Server status layer (`kCGWindowLayer == 25`) for instant discovery and per-display separator coordinates.
/// 2. Targeted Accessibility (`AXExtrasMenuBar`) discovery prioritizing known/accessory/proxy-matched apps
///    so cold startup completes in <60ms without stalling on App-Napped regular apps.
/// Excludes Control Center / WindowServer internal system modules by PID and localized name so Second Row & Search
/// stay strictly focused on user applications across all macOS locales.
@MainActor
final class MenuBarItemScanner {
    private nonisolated static let statusItemWindowLayer = 25
    private static let knownBundleIDsDefaultsKey = "eave.scanner.knownMenuBarBundleIDs"
    private static let maxPersistedKnownBundleIDs = 80

    /// Recognizes macOS Control Center owner names across system locales (supplementing PID-based detection).
    nonisolated static func isControlCenterOwnerName(_ ownerName: String) -> Bool {
        let lower = ownerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower == "control center"
            || lower == "控制中心"
            || lower == "コントロールセンター"
            || lower == "제어 센터"
            || lower == "centre de contrôle"
            || lower == "kontrollzentrum"
            || lower == "centro de control"
            || lower == "centro de controllo"
    }

    /// System daemons and non-menu-bar XPC/ViewService helpers that should be excluded from AX/window scanning.
    nonisolated static func isExcludedSystemOwner(bundleIdentifier: String?, ownerName: String) -> Bool {
        if let bundle = bundleIdentifier?.lowercased() {
            if bundle == "com.apple.controlcenter"
                || bundle == "com.apple.windowserver"
                || bundle == "com.apple.systemuiserver"
                || bundle == "com.apple.spotlight"
                || bundle == "com.apple.siri"
                || bundle.hasPrefix("com.apple.webkit.")
                || bundle.hasPrefix("com.apple.appkit.xpc.")
                || bundle.contains("viewservice")
                || bundle.contains("autofill")
                || bundle.contains("cursoruiviewservice") {
                return true
            }
        }
        if isControlCenterOwnerName(ownerName) {
            return true
        }
        let lowerOwner = ownerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowerOwner == "window server"
            || lowerOwner == "systemuiserver"
            || lowerOwner.contains("viewservice")
            || lowerOwner.hasPrefix("autofill (")
    }

    /// Raw snapshot of a CGWindowList layer-25 entry, isolated for deterministic unit testing.
    struct RawStatusWindow: Sendable {
        let windowID: CGWindowID
        let pid: pid_t
        let ownerName: String
        let windowName: String
        let bounds: CGRect
        let isOnScreen: Bool
    }

    /// Lightweight sendable process info gathered on MainActor before off-main AX scanning.
    struct RunningAppSnapshot: Sendable {
        let pid: pid_t
        let bundleIdentifier: String?
        let appName: String
        let isAccessory: Bool

        init(pid: pid_t, bundleIdentifier: String?, appName: String, isAccessory: Bool = false) {
            self.pid = pid
            self.bundleIdentifier = bundleIdentifier
            self.appName = appName
            self.isAccessory = isAccessory
        }
    }

    private struct WorkspaceSnapshot: Sendable {
        let runningApps: [RunningAppSnapshot]
        let controlCenterPIDs: Set<pid_t>
        let excludedSystemPIDs: Set<pid_t>
    }

    private let defaults: UserDefaults

    /// Cached PIDs known to own an `AXExtrasMenuBar` plus PIDs already checked since launch,
    /// cutting repeat AX scans from ~350ms down to <15ms.
    private var knownMenuBarPIDs = Set<pid_t>()
    private var scannedPIDs = Set<pid_t>()
    /// Persisted bundle identifiers confirmed to host status items on prior launches for instant cold startup.
    private var persistedKnownBundleIDs: Set<String>
    /// True when the latest scan located at least one Eave hidden-separator band window in WindowServer.
    private(set) var lastScanLocatedSeparatorBand: Bool = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Self.knownBundleIDsDefaultsKey) ?? []
        self.persistedKnownBundleIDs = Set(stored.map { $0.lowercased() })
    }

    /// Scans menu bar items off the main thread so Accessibility IPC never causes UI stutter.
    /// In fast mode (default), prioritizes proxy-matched, previously-known, and accessory apps so cold startup
    /// finishes in ~40–60ms instead of stalling on 100+ App-Napped regular apps.
    func scanAsync(
        hiddenSeparatorX: CGFloat?,
        excludingWindowIDs: Set<CGWindowID>,
        forceFullAXSweep: Bool = false
    ) async -> [MenuBarItemInfo] {
        let primaryHeight = NotchGeometryResolver.currentGeometry().menuBarHeight
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownBundleID = Bundle.main.bundleIdentifier?.lowercased() ?? "com.abcdlsj.eave"
        let axTrusted = AXIsProcessTrusted()

        let snapshot = captureWorkspaceSnapshot(ownPID: ownPID)
        let runningApps = snapshot.runningApps

        let livePIDs = Set(runningApps.map(\.pid))
        knownMenuBarPIDs.formIntersection(livePIDs)
        scannedPIDs.formIntersection(livePIDs)

        let priorityPIDs = knownMenuBarPIDs
        let persistedBundles = persistedKnownBundleIDs
        let alreadyScannedPIDs = scannedPIDs

        let result = await Task.detached(priority: .userInitiated) {
            Self.performBackgroundScan(
                runningApps: runningApps,
                controlCenterPIDs: snapshot.controlCenterPIDs,
                excludedSystemPIDs: snapshot.excludedSystemPIDs,
                knownMenuBarPIDs: priorityPIDs,
                persistedKnownBundleIDs: persistedBundles,
                scannedPIDs: alreadyScannedPIDs,
                forceFullAXSweep: forceFullAXSweep,
                menuBarHeight: primaryHeight,
                hiddenSeparatorX: hiddenSeparatorX,
                excludingWindowIDs: excludingWindowIDs,
                ownPID: ownPID,
                ownBundleID: ownBundleID,
                axTrusted: axTrusted
            )
        }.value

        lastScanLocatedSeparatorBand = result.locatedSeparatorBand
        if axTrusted {
            scannedPIDs.formUnion(result.probedAXPIDs)
            knownMenuBarPIDs.formUnion(result.discoveredAXPIDs)
            persistDiscoveredBundleIDs(from: result.items)
        }
        return result.items
    }

    /// Low-priority background pass that probes remaining unscanned regular apps once after startup
    /// so any newly installed regular app with a menu bar item is discovered without blocking launch.
    /// Returns `true` if at least one new menu-bar-owning process was discovered.
    func sweepUnscannedRegularAppsAsync() async -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let snapshot = captureWorkspaceSnapshot(ownPID: ownPID)
        let unscanned = snapshot.runningApps.filter { app in
            !scannedPIDs.contains(app.pid) && !knownMenuBarPIDs.contains(app.pid)
        }
        guard !unscanned.isEmpty else { return false }

        let discovered = await Task.detached(priority: .utility) {
            Self.probeAXExtrasOwnershipParallel(runningApps: unscanned, timeout: 0.035)
        }.value

        scannedPIDs.formUnion(unscanned.map(\.pid))
        guard !discovered.isEmpty else { return false }

        knownMenuBarPIDs.formUnion(discovered)
        let newlyKnownBundles = unscanned
            .filter { discovered.contains($0.pid) }
            .compactMap { $0.bundleIdentifier?.lowercased() }
        if !newlyKnownBundles.isEmpty {
            let beforeCount = persistedKnownBundleIDs.count
            persistedKnownBundleIDs.formUnion(newlyKnownBundles)
            if persistedKnownBundleIDs.count != beforeCount {
                savePersistedBundleIDs()
            }
        }
        return true
    }

    /// Synchronous convenience scan (used only when an immediate coordinate lookup is required).
    func scan(
        hiddenSeparatorX: CGFloat?,
        excludingWindowIDs: Set<CGWindowID>
    ) -> [MenuBarItemInfo] {
        let primaryHeight = NotchGeometryResolver.currentGeometry().menuBarHeight
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownBundleID = Bundle.main.bundleIdentifier?.lowercased() ?? "com.abcdlsj.eave"
        let snapshot = captureWorkspaceSnapshot(ownPID: ownPID)

        return Self.performBackgroundScan(
            runningApps: snapshot.runningApps,
            controlCenterPIDs: snapshot.controlCenterPIDs,
            excludedSystemPIDs: snapshot.excludedSystemPIDs,
            knownMenuBarPIDs: knownMenuBarPIDs,
            persistedKnownBundleIDs: persistedKnownBundleIDs,
            scannedPIDs: scannedPIDs,
            forceFullAXSweep: true,
            menuBarHeight: primaryHeight,
            hiddenSeparatorX: hiddenSeparatorX,
            excludingWindowIDs: excludingWindowIDs,
            ownPID: ownPID,
            ownBundleID: ownBundleID,
            axTrusted: AXIsProcessTrusted()
        ).items
    }

    private func captureWorkspaceSnapshot(ownPID: pid_t) -> WorkspaceSnapshot {
        var runningApps: [RunningAppSnapshot] = []
        var controlCenterPIDs = Set<pid_t>()
        var excludedSystemPIDs = Set<pid_t>()

        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            guard !app.isTerminated else { continue }
            let bundle = app.bundleIdentifier?.lowercased()
            let name = app.localizedName ?? app.bundleIdentifier ?? "App"

            if bundle == "com.apple.controlcenter" || Self.isControlCenterOwnerName(name) {
                controlCenterPIDs.insert(pid)
                excludedSystemPIDs.insert(pid)
                continue
            }

            if Self.isExcludedSystemOwner(bundleIdentifier: app.bundleIdentifier, ownerName: name) {
                excludedSystemPIDs.insert(pid)
                continue
            }

            guard pid != ownPID, app.activationPolicy != .prohibited else { continue }
            runningApps.append(
                RunningAppSnapshot(
                    pid: pid,
                    bundleIdentifier: app.bundleIdentifier,
                    appName: name,
                    isAccessory: app.activationPolicy == .accessory
                )
            )
        }

        return WorkspaceSnapshot(
            runningApps: runningApps,
            controlCenterPIDs: controlCenterPIDs,
            excludedSystemPIDs: excludedSystemPIDs
        )
    }

    private func persistDiscoveredBundleIDs(from items: [MenuBarItemInfo]) {
        let discoveredBundles = items.compactMap { $0.bundleIdentifier?.lowercased() }
        guard !discoveredBundles.isEmpty else { return }
        let before = persistedKnownBundleIDs.count
        persistedKnownBundleIDs.formUnion(discoveredBundles)
        if persistedKnownBundleIDs.count != before {
            savePersistedBundleIDs()
        }
    }

    private func savePersistedBundleIDs() {
        let trimmed = Array(persistedKnownBundleIDs.sorted().prefix(Self.maxPersistedKnownBundleIDs))
        defaults.set(trimmed, forKey: Self.knownBundleIDsDefaultsKey)
    }

    /// Per-display Eave hidden separator coordinates in CoreGraphics top-left global space.
    struct BandSeparator: Equatable, Sendable {
        let minY: CGFloat
        let height: CGFloat
        let hiddenMaxX: CGFloat
        let isCollapsed: Bool
    }

    private struct BackgroundScanResult: Sendable {
        let items: [MenuBarItemInfo]
        let discoveredAXPIDs: Set<pid_t>
        let probedAXPIDs: Set<pid_t>
        let locatedSeparatorBand: Bool
    }

    private nonisolated static func performBackgroundScan(
        runningApps: [RunningAppSnapshot],
        controlCenterPIDs: Set<pid_t>,
        excludedSystemPIDs: Set<pid_t>,
        knownMenuBarPIDs: Set<pid_t>,
        persistedKnownBundleIDs: Set<String>,
        scannedPIDs: Set<pid_t>,
        forceFullAXSweep: Bool,
        menuBarHeight: CGFloat,
        hiddenSeparatorX: CGFloat?,
        excludingWindowIDs: Set<CGWindowID>,
        ownPID: pid_t,
        ownBundleID: String,
        axTrusted: Bool
    ) -> BackgroundScanResult {
        let rawWindows = fetchRawStatusWindows()
        let bandSeparators = extractBandSeparators(
            from: rawWindows,
            ownBundleID: ownBundleID,
            controlCenterPIDs: controlCenterPIDs
        )

        let windowItems = parseStatusWindows(
            rawWindows,
            runningApps: runningApps,
            menuBarHeight: menuBarHeight,
            hiddenSeparatorX: hiddenSeparatorX,
            excludingWindowIDs: excludingWindowIDs,
            ownPID: ownPID,
            ownBundleID: ownBundleID,
            controlCenterPIDs: controlCenterPIDs,
            excludedSystemPIDs: excludedSystemPIDs
        )
        let windowItemPIDs = Set(windowItems.map(\.pid))

        let axCandidates: [RunningAppSnapshot]
        if forceFullAXSweep {
            axCandidates = runningApps
        } else {
            // Fast path: probe known menu-bar apps, apps already detected in WindowServer layer 25,
            // previously persisted menu-bar apps, and newly launched accessory utilities.
            axCandidates = runningApps.filter { app in
                if knownMenuBarPIDs.contains(app.pid) || windowItemPIDs.contains(app.pid) {
                    return true
                }
                if let bid = app.bundleIdentifier?.lowercased(), persistedKnownBundleIDs.contains(bid) {
                    return true
                }
                return app.isAccessory && !scannedPIDs.contains(app.pid)
            }
        }

        var discovered: [MenuBarItemInfo] = []
        var axPIDs = Set<pid_t>()

        if axTrusted && !axCandidates.isEmpty {
            discovered = scanAccessibilityExtrasParallel(
                runningApps: axCandidates,
                hiddenSeparatorX: hiddenSeparatorX,
                bandSeparators: bandSeparators,
                timeout: 0.035
            )
            axPIDs = Set(discovered.map(\.pid))
        }

        for winItem in windowItems {
            let alreadyPresent = discovered.contains { existing in
                if existing.pid == winItem.pid {
                    return abs(existing.frame.midX - winItem.frame.midX) < 16
                        || (existing.bundleIdentifier != nil && existing.bundleIdentifier == winItem.bundleIdentifier)
                }
                return false
            }
            if !alreadyPresent {
                discovered.append(winItem)
            }
        }

        return BackgroundScanResult(
            items: discovered.sorted { $0.frame.minX < $1.frame.minX },
            discoveredAXPIDs: axPIDs,
            probedAXPIDs: Set(axCandidates.map(\.pid)),
            locatedSeparatorBand: !bandSeparators.isEmpty
        )
    }

    // MARK: - Track 1: CGWindowList

    nonisolated static func fetchRawStatusWindows() -> [RawStatusWindow] {
        guard let rawList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var rawWindows: [RawStatusWindow] = []
        rawWindows.reserveCapacity(64)

        for entry in rawList {
            guard let layer = entry[kCGWindowLayer as String] as? Int,
                  layer == statusItemWindowLayer,
                  let windowNumber = entry[kCGWindowNumber as String] as? UInt32,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }

            let ownerName = (entry[kCGWindowOwnerName as String] as? String) ?? ""
            let windowName = (entry[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let isOnScreen = (entry[kCGWindowIsOnscreen as String] as? Bool) ?? false

            rawWindows.append(
                RawStatusWindow(
                    windowID: windowNumber,
                    pid: pid,
                    ownerName: ownerName,
                    windowName: windowName,
                    bounds: bounds,
                    isOnScreen: isOnScreen
                )
            )
        }
        return rawWindows
    }

    /// Extracts per-display Eave hidden separator coordinates from Control Center proxy windows so
    /// both Track 1 (CGWindowList) and Track 2 (AXExtrasMenuBar) classify each item against its own display's separator.
    nonisolated static func extractBandSeparators(
        from rawWindows: [RawStatusWindow],
        ownBundleID: String = "com.abcdlsj.eave",
        controlCenterPIDs: Set<pid_t> = []
    ) -> [BandSeparator] {
        let lowerOwnBundle = ownBundleID.lowercased()
        var bandSeparators: [BandSeparator] = []
        var eaveBandWindows: [(minY: CGFloat, height: CGFloat, bounds: CGRect, name: String)] = []

        for win in rawWindows {
            let isControlCenter = controlCenterPIDs.contains(win.pid) || isControlCenterOwnerName(win.ownerName)
            guard isControlCenter else { continue }
            guard !(win.bounds.minX == 0 && win.bounds.minY == 0) else { continue }
            let lowerName = win.windowName.lowercased()
            if lowerName == "eave.control.hidden" || lowerName == lowerOwnBundle {
                eaveBandWindows.append((win.bounds.minY, win.bounds.height, win.bounds, lowerName))
            }
        }

        for candidate in eaveBandWindows {
            if candidate.name == "eave.control.hidden" || candidate.bounds.width >= 200 {
                bandSeparators.append(
                    BandSeparator(
                        minY: candidate.minY,
                        height: candidate.height,
                        hiddenMaxX: candidate.bounds.maxX,
                        isCollapsed: candidate.bounds.width >= 200
                    )
                )
            }
        }

        // When expanded, Eave's hidden separator on secondary displays is a small (< 200pt) window
        // named with `ownBundleID` to the left of Eave's toggle item on the same display band.
        for candidate in eaveBandWindows where candidate.name == lowerOwnBundle && candidate.bounds.width < 200 {
            let hasBandSep = bandSeparators.contains {
                abs($0.minY - candidate.minY) <= 4 && abs($0.height - candidate.height) <= 4
            }
            if !hasBandSep {
                let peers = eaveBandWindows.filter {
                    $0.name == lowerOwnBundle
                        && abs($0.minY - candidate.minY) <= 4
                        && abs($0.height - candidate.height) <= 4
                }
                if peers.count >= 2, let leftmost = peers.min(by: { $0.bounds.minX < $1.bounds.minX }) {
                    bandSeparators.append(
                        BandSeparator(
                            minY: leftmost.minY,
                            height: leftmost.height,
                            hiddenMaxX: leftmost.bounds.maxX,
                            isCollapsed: false
                        )
                    )
                }
            }
        }

        return bandSeparators
    }

    /// Resolves the separator X coordinate for an item frame across multi-monitor coordinate spaces.
    nonisolated static func resolveSeparatorX(
        for frame: CGRect,
        bandSeparators: [BandSeparator],
        fallbackHiddenSeparatorX: CGFloat?
    ) -> CGFloat? {
        // 1. Exact vertical menu-bar band match (CG top-left coordinates).
        if let exact = bandSeparators.first(where: {
            abs($0.minY - frame.minY) <= 8 && abs($0.height - frame.height) <= 10
        }) {
            return exact.hiddenMaxX
        }
        // 2. Vertical band match by minY alone (AX items sometimes report inner button height slightly smaller than bar height).
        if let byY = bandSeparators.first(where: { abs($0.minY - frame.minY) <= 10 }) {
            return byY.hiddenMaxX
        }
        // 3. Fallback only when frame lies on the primary display band (minY near 0); never compare a left-side
        //    secondary monitor's negative X coordinate against the primary display's positive separator X.
        if abs(frame.minY) <= 12 {
            return fallbackHiddenSeparatorX
        }
        return nil
    }

    /// Pure parser handling both classic third-party status windows AND macOS 26 Tahoe's
    /// Control Center proxy status windows (where `ownerName` is Control Center / localized equivalent
    /// and `windowName` carries the owning app's bundle identifier or PID).
    nonisolated static func parseStatusWindows(
        _ rawWindows: [RawStatusWindow],
        runningApps: [RunningAppSnapshot],
        menuBarHeight: CGFloat,
        hiddenSeparatorX: CGFloat?,
        excludingWindowIDs: Set<CGWindowID>,
        ownPID: pid_t,
        ownBundleID: String = "com.abcdlsj.eave",
        controlCenterPIDs: Set<pid_t> = [],
        excludedSystemPIDs: Set<pid_t> = []
    ) -> [MenuBarItemInfo] {
        let appByPID = Dictionary(uniqueKeysWithValues: runningApps.map { ($0.pid, $0) })
        var appByBundleID: [String: RunningAppSnapshot] = [:]
        for app in runningApps {
            if let bid = app.bundleIdentifier?.lowercased(), !bid.isEmpty {
                appByBundleID[bid] = app
            }
        }

        let maxBarY = max(menuBarHeight + 10, 46)
        let lowerOwnBundle = ownBundleID.lowercased()
        let bandSeparators = extractBandSeparators(
            from: rawWindows,
            ownBundleID: ownBundleID,
            controlCenterPIDs: controlCenterPIDs
        )

        // Prioritize on-screen proxy windows first so multi-monitor deduplication picks the active display copy.
        let orderedWindows = rawWindows.sorted { lhs, rhs in
            if lhs.isOnScreen != rhs.isOnScreen {
                return lhs.isOnScreen && !rhs.isOnScreen
            }
            return abs(lhs.bounds.minY) < abs(rhs.bounds.minY)
        }

        var results: [MenuBarItemInfo] = []
        var seenProxyKeys = Set<String>()

        for win in orderedWindows {
            guard !excludingWindowIDs.contains(win.windowID) else { continue }
            let bounds = win.bounds
            guard bounds.width >= 4, bounds.width <= 320,
                  bounds.height >= 8, bounds.height <= maxBarY,
                  !(bounds.minX == 0 && bounds.minY == 0) else {
                continue
            }

            let isControlCenter = controlCenterPIDs.contains(win.pid) || isControlCenterOwnerName(win.ownerName)

            // Track 1A: macOS 26 Tahoe Control Center proxy windows whose windowName is a third-party bundle ID or PID.
            // Unmatched Control Center windows (Clock, BentoBox-0, Item-0, empty) are strictly discarded here
            // so they NEVER leak into Track 1B as "Control Center" entries on any locale.
            if isControlCenter {
                let rawName = win.windowName
                let lowerName = rawName.lowercased()
                guard !lowerName.isEmpty, lowerName != lowerOwnBundle else {
                    continue
                }

                let proxiedApp: RunningAppSnapshot?
                if let byBundle = appByBundleID[lowerName] {
                    proxiedApp = byBundle
                } else if let numericPID = pid_t(rawName), let byPID = appByPID[numericPID] {
                    proxiedApp = byPID
                } else {
                    proxiedApp = nil
                }

                guard let proxiedApp,
                      !isExcludedSystemOwner(bundleIdentifier: proxiedApp.bundleIdentifier, ownerName: proxiedApp.appName) else {
                    continue
                }

                let dedupKey = proxiedApp.bundleIdentifier?.lowercased() ?? "pid.\(proxiedApp.pid)"
                guard seenProxyKeys.insert(dedupKey).inserted else { continue }

                let sepX = resolveSeparatorX(
                    for: bounds,
                    bandSeparators: bandSeparators,
                    fallbackHiddenSeparatorX: hiddenSeparatorX
                )
                let section: MenuBarSection
                if let sepX {
                    section = MenuBarSearchEngine.classifySection(
                        itemMidX: bounds.midX,
                        hiddenSeparatorX: sepX
                    )
                } else if !win.isOnScreen {
                    section = .hidden
                } else {
                    section = .visible
                }

                results.append(
                    MenuBarItemInfo(
                        id: "cc.\(proxiedApp.pid).\(dedupKey)",
                        windowID: win.windowID,
                        pid: proxiedApp.pid,
                        bundleIdentifier: proxiedApp.bundleIdentifier,
                        appName: proxiedApp.appName,
                        title: "",
                        frame: bounds,
                        section: section
                    )
                )
                continue
            }

            // Track 1B: Classic directly-owned third-party status windows (macOS 15 and direct apps).
            guard win.pid != ownPID,
                  !excludedSystemPIDs.contains(win.pid),
                  bounds.minY >= -4, bounds.minY <= maxBarY else {
                continue
            }

            let snap = appByPID[win.pid]
            let ownerName = !win.ownerName.isEmpty ? win.ownerName : (snap?.appName ?? "Unknown")
            let bundleID = snap?.bundleIdentifier

            if isExcludedSystemOwner(bundleIdentifier: bundleID, ownerName: ownerName) {
                continue
            }

            let sepX = resolveSeparatorX(
                for: bounds,
                bandSeparators: bandSeparators,
                fallbackHiddenSeparatorX: hiddenSeparatorX
            )
            let section = MenuBarSearchEngine.classifySection(
                itemMidX: bounds.midX,
                hiddenSeparatorX: sepX
            )

            results.append(
                MenuBarItemInfo(
                    id: "win.\(win.windowID)",
                    windowID: win.windowID,
                    pid: win.pid,
                    bundleIdentifier: bundleID,
                    appName: ownerName,
                    title: win.windowName,
                    frame: bounds,
                    section: section
                )
            )
        }

        return results
    }

    // MARK: - Track 2: Parallel AXExtrasMenuBar (Hard 35ms Timeout per Process)

    private final class LockedItemCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [MenuBarItemInfo] = []

        func append(contentsOf items: [MenuBarItemInfo]) {
            guard !items.isEmpty else { return }
            lock.lock()
            storage.append(contentsOf: items)
            lock.unlock()
        }

        func drain() -> [MenuBarItemInfo] {
            lock.lock()
            let result = storage
            lock.unlock()
            return result
        }
    }

    private final class LockedPIDCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = Set<pid_t>()

        func insert(_ pid: pid_t) {
            lock.lock()
            storage.insert(pid)
            lock.unlock()
        }

        func drain() -> Set<pid_t> {
            lock.lock()
            let result = storage
            lock.unlock()
            return result
        }
    }

    private nonisolated static func probeAXExtrasOwnershipParallel(
        runningApps: [RunningAppSnapshot],
        timeout: Float
    ) -> Set<pid_t> {
        let collector = LockedPIDCollector()
        DispatchQueue.concurrentPerform(iterations: runningApps.count) { idx in
            let app = runningApps[idx]
            let appElement = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(appElement, timeout)

            var extrasRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasRef) == .success,
                  let extrasRef else {
                return
            }

            let extrasBar = extrasRef as! AXUIElement
            AXUIElementSetMessagingTimeout(extrasBar, timeout)

            var childrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(extrasBar, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                  let children = childrenRef as? [AXUIElement], !children.isEmpty else {
                return
            }
            collector.insert(app.pid)
        }
        return collector.drain()
    }

    private nonisolated static func scanAccessibilityExtrasParallel(
        runningApps: [RunningAppSnapshot],
        hiddenSeparatorX: CGFloat?,
        bandSeparators: [BandSeparator],
        timeout: Float = 0.035
    ) -> [MenuBarItemInfo] {
        let collector = LockedItemCollector()
        DispatchQueue.concurrentPerform(iterations: runningApps.count) { idx in
            let app = runningApps[idx]
            let appElement = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(appElement, timeout)

            var extrasRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasRef) == .success,
                  let extrasRef else {
                return
            }

            let extrasBar = extrasRef as! AXUIElement
            AXUIElementSetMessagingTimeout(extrasBar, timeout)

            var childrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(extrasBar, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                  let children = childrenRef as? [AXUIElement], !children.isEmpty else {
                return
            }

            var appItems: [MenuBarItemInfo] = []
            appItems.reserveCapacity(children.count)
            for (index, item) in children.enumerated() {
                AXUIElementSetMessagingTimeout(item, timeout)
                guard let frame = axFrame(of: item), frame.width >= 4 else { continue }
                let title = axString(item, kAXTitleAttribute)
                    ?? axString(item, kAXDescriptionAttribute)
                    ?? ""

                let sepX = resolveSeparatorX(
                    for: frame,
                    bandSeparators: bandSeparators,
                    fallbackHiddenSeparatorX: hiddenSeparatorX
                )
                let section = MenuBarSearchEngine.classifySection(
                    itemMidX: frame.midX,
                    hiddenSeparatorX: sepX
                )

                appItems.append(
                    MenuBarItemInfo(
                        id: "ax.\(app.pid).\(index)",
                        windowID: 0,
                        pid: app.pid,
                        bundleIdentifier: app.bundleIdentifier,
                        appName: app.appName,
                        title: title,
                        frame: frame,
                        section: section
                    )
                )
            }
            collector.append(contentsOf: appItems)
        }

        return collector.drain()
    }

    private nonisolated static func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        let trimmed = (ref as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private nonisolated static func axFrame(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef else {
            return nil
        }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: point, size: size)
    }
}
