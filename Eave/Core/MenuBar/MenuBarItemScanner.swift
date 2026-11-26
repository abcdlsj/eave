import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Pure section classifier & fuzzy search engine (isolated for deterministic unit tests).
enum MenuBarSearchEngine {
    /// Classifies an item's X coordinate relative to Eave's separator positions.
    static func classifySection(
        itemMidX: CGFloat,
        hiddenSeparatorX: CGFloat?,
        alwaysHiddenSeparatorX: CGFloat?
    ) -> MenuBarSection {
        if let alwaysX = alwaysHiddenSeparatorX, itemMidX < alwaysX {
            return .alwaysHidden
        }
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
        case .alwaysHidden: 1
        case .visible: 2
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
/// 1. Accessibility (`AXExtrasMenuBar`) primary discovery (reliable for third-party items on macOS 26 Tahoe).
/// 2. Window Server status layer (`kCGWindowLayer == 25`) supplement when Accessibility is unavailable.
/// Excludes Control Center / WindowServer internal system modules so Notch Bar stays focused on user apps.
@MainActor
final class MenuBarItemScanner {
    private nonisolated static let statusItemWindowLayer = 25

    /// System daemons whose internal menu bar modules should be excluded from Eave's Notch Bar & Search.
    nonisolated static func isExcludedSystemOwner(bundleIdentifier: String?, ownerName: String) -> Bool {
        if let bundle = bundleIdentifier?.lowercased() {
            if bundle == "com.apple.controlcenter"
                || bundle == "com.apple.windowserver"
                || bundle == "com.apple.systemuiserver"
                || bundle == "com.apple.spotlight"
                || bundle == "com.apple.siri" {
                return true
            }
        }
        let lowerOwner = ownerName.lowercased()
        return lowerOwner == "control center"
            || lowerOwner == "window server"
            || lowerOwner == "systemuiserver"
    }

    /// Lightweight sendable process info gathered on MainActor before off-main AX scanning.
    private struct RunningAppSnapshot: Sendable {
        let pid: pid_t
        let bundleIdentifier: String?
        let appName: String
    }

    /// Scans menu bar items off the main thread so Accessibility IPC never causes UI stutter.
    func scanAsync(
        hiddenSeparatorX: CGFloat?,
        alwaysHiddenSeparatorX: CGFloat?,
        excludingWindowIDs: Set<CGWindowID>
    ) async -> [MenuBarItemInfo] {
        let primaryHeight = NotchGeometryResolver.currentGeometry().menuBarHeight
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let axTrusted = AXIsProcessTrusted()

        // Snapshot running apps quickly on MainActor (microseconds), then do all IPC off-main.
        let runningApps: [RunningAppSnapshot] = NSWorkspace.shared.runningApplications.compactMap { app in
            let pid = app.processIdentifier
            guard pid != ownPID, !app.isTerminated else { return nil }
            let name = app.localizedName ?? app.bundleIdentifier ?? "App"
            if Self.isExcludedSystemOwner(bundleIdentifier: app.bundleIdentifier, ownerName: name) {
                return nil
            }
            return RunningAppSnapshot(pid: pid, bundleIdentifier: app.bundleIdentifier, appName: name)
        }

        return await Task.detached(priority: .utility) {
            Self.performBackgroundScan(
                runningApps: runningApps,
                menuBarHeight: primaryHeight,
                hiddenSeparatorX: hiddenSeparatorX,
                alwaysHiddenSeparatorX: alwaysHiddenSeparatorX,
                excludingWindowIDs: excludingWindowIDs,
                ownPID: ownPID,
                axTrusted: axTrusted
            )
        }.value
    }

    /// Synchronous convenience scan (used only when an immediate coordinate lookup is required).
    func scan(
        hiddenSeparatorX: CGFloat?,
        alwaysHiddenSeparatorX: CGFloat?,
        excludingWindowIDs: Set<CGWindowID>
    ) -> [MenuBarItemInfo] {
        let primaryHeight = NotchGeometryResolver.currentGeometry().menuBarHeight
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let runningApps: [RunningAppSnapshot] = NSWorkspace.shared.runningApplications.compactMap { app in
            let pid = app.processIdentifier
            guard pid != ownPID, !app.isTerminated else { return nil }
            let name = app.localizedName ?? app.bundleIdentifier ?? "App"
            if Self.isExcludedSystemOwner(bundleIdentifier: app.bundleIdentifier, ownerName: name) {
                return nil
            }
            return RunningAppSnapshot(pid: pid, bundleIdentifier: app.bundleIdentifier, appName: name)
        }
        return Self.performBackgroundScan(
            runningApps: runningApps,
            menuBarHeight: primaryHeight,
            hiddenSeparatorX: hiddenSeparatorX,
            alwaysHiddenSeparatorX: alwaysHiddenSeparatorX,
            excludingWindowIDs: excludingWindowIDs,
            ownPID: ownPID,
            axTrusted: AXIsProcessTrusted()
        )
    }

    private nonisolated static func performBackgroundScan(
        runningApps: [RunningAppSnapshot],
        menuBarHeight: CGFloat,
        hiddenSeparatorX: CGFloat?,
        alwaysHiddenSeparatorX: CGFloat?,
        excludingWindowIDs: Set<CGWindowID>,
        ownPID: pid_t,
        axTrusted: Bool
    ) -> [MenuBarItemInfo] {
        var discovered: [MenuBarItemInfo] = []

        if axTrusted {
            discovered = scanAccessibilityExtras(
                runningApps: runningApps,
                hiddenSeparatorX: hiddenSeparatorX,
                alwaysHiddenSeparatorX: alwaysHiddenSeparatorX
            )
        }

        let appByPID = Dictionary(uniqueKeysWithValues: runningApps.map { ($0.pid, $0) })
        let windowItems = scanWindowList(
            appByPID: appByPID,
            menuBarHeight: menuBarHeight,
            hiddenSeparatorX: hiddenSeparatorX,
            alwaysHiddenSeparatorX: alwaysHiddenSeparatorX,
            excludingWindowIDs: excludingWindowIDs,
            ownPID: ownPID
        )

        for winItem in windowItems {
            let alreadyPresent = discovered.contains { existing in
                existing.pid == winItem.pid && abs(existing.frame.midX - winItem.frame.midX) < 16
            }
            if !alreadyPresent {
                discovered.append(winItem)
            }
        }

        return discovered.sorted { $0.frame.minX < $1.frame.minX }
    }

    // MARK: - Track 1: CGWindowList

    private nonisolated static func scanWindowList(
        appByPID: [pid_t: RunningAppSnapshot],
        menuBarHeight: CGFloat,
        hiddenSeparatorX: CGFloat?,
        alwaysHiddenSeparatorX: CGFloat?,
        excludingWindowIDs: Set<CGWindowID>,
        ownPID: pid_t
    ) -> [MenuBarItemInfo] {
        guard let rawList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let maxBarY = max(menuBarHeight + 10, 46)
        var results: [MenuBarItemInfo] = []

        for entry in rawList {
            guard let layer = entry[kCGWindowLayer as String] as? Int,
                  layer == statusItemWindowLayer,
                  let windowNumber = entry[kCGWindowNumber as String] as? UInt32,
                  !excludingWindowIDs.contains(windowNumber),
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ownPID,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }

            guard bounds.width >= 4, bounds.width <= 320,
                  bounds.height >= 8, bounds.height <= maxBarY,
                  bounds.minY >= -4, bounds.minY <= maxBarY,
                  !(bounds.minX == 0 && bounds.minY == 0) else {
                continue
            }

            let snap = appByPID[pid]
            let ownerName = (entry[kCGWindowOwnerName as String] as? String)
                ?? snap?.appName
                ?? "Unknown"
            let bundleID = snap?.bundleIdentifier

            if isExcludedSystemOwner(bundleIdentifier: bundleID, ownerName: ownerName) {
                continue
            }

            let title = (entry[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let section = MenuBarSearchEngine.classifySection(
                itemMidX: bounds.midX,
                hiddenSeparatorX: hiddenSeparatorX,
                alwaysHiddenSeparatorX: alwaysHiddenSeparatorX
            )

            results.append(
                MenuBarItemInfo(
                    id: "win.\(windowNumber)",
                    windowID: windowNumber,
                    pid: pid,
                    bundleIdentifier: bundleID,
                    appName: ownerName,
                    title: title,
                    frame: bounds,
                    section: section
                )
            )
        }

        return results
    }

    // MARK: - Track 2: AXExtrasMenuBar

    private nonisolated static func scanAccessibilityExtras(
        runningApps: [RunningAppSnapshot],
        hiddenSeparatorX: CGFloat?,
        alwaysHiddenSeparatorX: CGFloat?
    ) -> [MenuBarItemInfo] {
        var results: [MenuBarItemInfo] = []

        for app in runningApps {
            let appElement = AXUIElementCreateApplication(app.pid)
            var extrasRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasRef) == .success,
                  let extrasRef else {
                continue
            }

            let extrasBar = extrasRef as! AXUIElement
            var childrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(extrasBar, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                  let children = childrenRef as? [AXUIElement] else {
                continue
            }

            for (index, item) in children.enumerated() {
                guard let frame = axFrame(of: item), frame.width >= 4 else { continue }
                let title = axString(item, kAXTitleAttribute)
                    ?? axString(item, kAXDescriptionAttribute)
                    ?? ""

                let section = MenuBarSearchEngine.classifySection(
                    itemMidX: frame.midX,
                    hiddenSeparatorX: hiddenSeparatorX,
                    alwaysHiddenSeparatorX: alwaysHiddenSeparatorX
                )

                results.append(
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
        }

        return results
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
