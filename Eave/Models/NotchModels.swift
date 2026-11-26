import CoreGraphics
import Foundation

/// Exact geometry of the primary display's physical notch or floating fallback pill.
struct NotchGeometry: Equatable, Sendable {
    let screenFrame: CGRect
    let notchRect: CGRect
    let isPhysicalNotch: Bool
    let menuBarHeight: CGFloat

    /// Anchor point at the top-center of the notch in AppKit screen coordinates.
    var topCenter: CGPoint {
        CGPoint(x: notchRect.midX, y: screenFrame.maxY)
    }

    /// Computes notch geometry from raw screen metrics (pure function for unit testing).
    static func resolve(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeft: CGRect?,
        auxiliaryTopRight: CGRect?
    ) -> NotchGeometry {
        if safeAreaTop > 0,
           let left = auxiliaryTopLeft,
           let right = auxiliaryTopRight,
           right.minX > left.maxX {
            let notchWidth = right.minX - left.maxX
            let notchRect = CGRect(
                x: left.maxX,
                y: screenFrame.maxY - safeAreaTop,
                width: notchWidth,
                height: safeAreaTop
            )
            return NotchGeometry(
                screenFrame: screenFrame,
                notchRect: notchRect,
                isPhysicalNotch: true,
                menuBarHeight: safeAreaTop
            )
        }

        // Non-notched fallback: sleek floating pill anchored near the top-center of the screen.
        let fallbackMenuBar: CGFloat = 28
        let pillWidth: CGFloat = 180
        let pillHeight: CGFloat = 30
        let pillRect = CGRect(
            x: screenFrame.midX - pillWidth / 2,
            y: screenFrame.maxY - fallbackMenuBar - pillHeight - 6,
            width: pillWidth,
            height: pillHeight
        )
        return NotchGeometry(
            screenFrame: screenFrame,
            notchRect: pillRect,
            isPhysicalNotch: false,
            menuBarHeight: fallbackMenuBar
        )
    }
}

/// Origin of a Notch alert or ambient indicator.
enum NotchAlertSource: String, Sendable, Equatable, Codable {
    case dockBadge
    case menuBarAX
    case bridge
    case system
}

/// Visual style for a textless Notch right-wing indicator when no numeric badge is provided.
enum NotchSignalStyle: String, Sendable, Equatable, Codable {
    /// Quiet accent dot (default; one-shot or looped sonar ping).
    case dot
    /// Minimal 3-bar breathing wave for active background work (e.g. AI agents, builds).
    case wave
}

/// Transient textless notification signal presented as single-line wings flanking the hardware notch.
struct NotchAlert: Identifiable, Equatable, Sendable {
    let id: String
    let source: NotchAlertSource
    /// Optional numeric badge (e.g. "3", "99+"). When nil, renders a clean accent indicator dot or wave.
    let badge: String?
    /// Visual style when `badge` is nil (defaults to `.dot`).
    let style: NotchSignalStyle
    /// When true, gently repeats the rim shimmer and sonar ping while the alert stays visible.
    let loop: Bool
    /// Optional local image file path for custom sender icon.
    let iconPath: String?
    /// Optional SF Symbol name.
    let symbolName: String?
    /// Optional `#RRGGBB` hex color for the indicator dot, wave, or badge pill.
    let accentHex: String?
    /// Optional owning application bundle identifier (used for icon fallback and click activation).
    let bundleIdentifier: String?
    /// Optional callback URL opened when clicking the Notch wings.
    let targetURL: URL?
    let duration: TimeInterval
    let timestamp: Date

    init(
        id: String = UUID().uuidString,
        source: NotchAlertSource,
        badge: String? = nil,
        style: NotchSignalStyle = .dot,
        loop: Bool = false,
        iconPath: String? = nil,
        symbolName: String? = nil,
        accentHex: String? = nil,
        bundleIdentifier: String? = nil,
        targetURL: URL? = nil,
        duration: TimeInterval = 4.5,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.badge = BridgePayload.sanitizedNumericBadge(badge)
        self.style = style
        self.loop = loop
        self.iconPath = iconPath
        self.symbolName = symbolName
        self.accentHex = accentHex
        self.bundleIdentifier = bundleIdentifier
        self.targetURL = targetURL
        self.duration = max(1.0, min(duration, 300.0))
        self.timestamp = timestamp
    }
}

/// Persistent low-profile visual signal flanking the hardware notch (icon + accent dot, wave, or optional count).
struct AmbientIndicator: Identifiable, Equatable, Sendable {
    let id: String
    let source: NotchAlertSource
    let badge: String?
    let style: NotchSignalStyle
    /// When true, repeats the subtle rim shimmer and sonar ping periodically while active.
    let loop: Bool
    let iconPath: String?
    let symbolName: String?
    let accentHex: String?
    let bundleIdentifier: String?
    let targetURL: URL?
    /// Optional auto-expiry time in seconds (`nil` persists until explicitly cleared).
    let duration: TimeInterval?

    init(
        id: String,
        source: NotchAlertSource,
        badge: String? = nil,
        style: NotchSignalStyle = .dot,
        loop: Bool = false,
        iconPath: String? = nil,
        symbolName: String? = nil,
        accentHex: String? = nil,
        bundleIdentifier: String? = nil,
        targetURL: URL? = nil,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.source = source
        self.badge = BridgePayload.sanitizedNumericBadge(badge)
        self.style = style
        self.loop = loop
        self.iconPath = iconPath
        self.symbolName = symbolName
        self.accentHex = accentHex
        self.bundleIdentifier = bundleIdentifier
        self.targetURL = targetURL
        self.duration = duration.map { max(1.0, min($0, 300.0)) }
    }
}

/// Unified state of the Notch panel (strictly single-line hardware-height wings; no text sheets).
enum NotchState: Equatable, Sendable {
    case idle
    case ambient([AmbientIndicator])
    case peek(NotchAlert)
}

/// Mode requested by an external NotchBridge payload.
enum BridgeMode: String, Sendable, Equatable {
    case peek
    case ambient
    case clear
}

/// Parsed textless payload from URL Scheme (`eave://notify?...`) or DistributedNotification.
/// Accepts only icon (`icon` / `symbol` / `bundleID`), callback (`url`), accent color (`accent`),
/// optional numeric badge (`badge`), visual style (`style`), effect looping (`loop`), duration, mode, and id.
struct BridgePayload: Equatable, Sendable {
    let id: String
    let mode: BridgeMode
    let badge: String?
    let style: NotchSignalStyle
    let loop: Bool
    let iconPath: String?
    let symbolName: String?
    let accentHex: String?
    let bundleIdentifier: String?
    let targetURL: URL?
    /// Explicit duration in seconds (`nil` uses default 4.5s for peek, or persistent until clear for ambient).
    let duration: TimeInterval?

    /// Enforces strictly numeric badges (e.g. "1", "24", "99+") so arbitrary text cannot appear in the Notch.
    static func sanitizedNumericBadge(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 4 else { return nil }

        let chars = Array(trimmed)
        var hasDigit = false
        for (idx, ch) in chars.enumerated() {
            if ch.isASCII && ch.isNumber {
                hasDigit = true
            } else if ch == "+" && idx == chars.count - 1 && hasDigit {
                continue
            } else {
                return nil
            }
        }
        return hasDigit ? trimmed : nil
    }

    private static func parseBool(_ raw: String?) -> Bool {
        guard let raw else { return false }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on": return true
        default: return false
        }
    }

    /// Parses an `eave://notify?...` or `eave://clear?...` URL.
    static func parse(url: URL) -> BridgePayload? {
        guard url.scheme?.lowercased() == "eave",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let host = (components.host ?? "").lowercased()
        let items = Dictionary(
            (components.queryItems ?? []).compactMap { item -> (String, String)? in
                guard let value = item.value, !value.isEmpty else { return nil }
                let key = item.name.lowercased()
                return (key, value)
            },
            uniquingKeysWith: { _, latest in latest }
        )

        let mode: BridgeMode
        if host == "clear" || items["mode"]?.lowercased() == "clear" {
            mode = .clear
        } else if items["mode"]?.lowercased() == "ambient" {
            mode = .ambient
        } else if host == "notify" || host.isEmpty {
            mode = .peek
        } else {
            return nil
        }

        let id = items["id"] ?? items["bundleid"] ?? UUID().uuidString
        let rawDuration = items["duration"].flatMap(Double.init)
        let clampedDuration = rawDuration.map { max(1.0, min($0, 300.0)) }
        let targetURL = items["url"].flatMap(URL.init(string:))
        let style = items["style"].flatMap { NotchSignalStyle(rawValue: $0.lowercased()) } ?? .dot
        let loop = parseBool(items["loop"])

        return BridgePayload(
            id: id,
            mode: mode,
            badge: sanitizedNumericBadge(items["badge"]),
            style: style,
            loop: loop,
            iconPath: items["icon"],
            symbolName: items["symbol"],
            accentHex: items["accent"],
            bundleIdentifier: items["bundleid"],
            targetURL: targetURL,
            duration: clampedDuration
        )
    }

    /// Parses a `DistributedNotificationCenter` `userInfo` dictionary.
    static func parse(userInfo: [AnyHashable: Any]) -> BridgePayload? {
        func string(_ key: String) -> String? {
            if let value = userInfo[key] as? String, !value.isEmpty { return value }
            if let num = userInfo[key] as? Int { return String(num) }
            return nil
        }

        let modeRaw = string("mode")?.lowercased() ?? "peek"
        let mode = BridgeMode(rawValue: modeRaw) ?? .peek
        let id = string("id") ?? string("bundleID") ?? string("bundleId") ?? UUID().uuidString
        let style = string("style").flatMap { NotchSignalStyle(rawValue: $0.lowercased()) } ?? .dot

        let loop: Bool
        if let flag = userInfo["loop"] as? Bool {
            loop = flag
        } else {
            loop = parseBool(string("loop"))
        }

        let rawDuration: Double?
        if let num = userInfo["duration"] as? Double {
            rawDuration = num
        } else if let str = string("duration"), let num = Double(str) {
            rawDuration = num
        } else {
            rawDuration = nil
        }
        let clampedDuration = rawDuration.map { max(1.0, min($0, 300.0)) }

        return BridgePayload(
            id: id,
            mode: mode,
            badge: sanitizedNumericBadge(string("badge")),
            style: style,
            loop: loop,
            iconPath: string("icon") ?? string("iconPath"),
            symbolName: string("symbol"),
            accentHex: string("accent"),
            bundleIdentifier: string("bundleID") ?? string("bundleId"),
            targetURL: string("url").flatMap(URL.init(string:)),
            duration: clampedDuration
        )
    }
}
