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
enum NotchAlertSource: String, Sendable, Codable {
    case dockBadge
    case menuBarAX
    case bridge
    case system
}

/// Transient notification presented as a Notch Peek wing + optional expanded card.
struct NotchAlert: Identifiable, Equatable, Sendable {
    let id: String
    let source: NotchAlertSource
    let title: String
    let subtitle: String?
    let badge: String?
    let symbolName: String?
    let accentHex: String?
    let bundleIdentifier: String?
    let targetURL: URL?
    let duration: TimeInterval
    let timestamp: Date

    init(
        id: String = UUID().uuidString,
        source: NotchAlertSource,
        title: String,
        subtitle: String? = nil,
        badge: String? = nil,
        symbolName: String? = nil,
        accentHex: String? = nil,
        bundleIdentifier: String? = nil,
        targetURL: URL? = nil,
        duration: TimeInterval = 4.5,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.symbolName = symbolName
        self.accentHex = accentHex
        self.bundleIdentifier = bundleIdentifier
        self.targetURL = targetURL
        self.duration = max(1.5, min(duration, 30.0))
        self.timestamp = timestamp
    }
}

/// Persistent low-profile status dot shown along the edge of the notch.
struct AmbientIndicator: Identifiable, Equatable, Sendable {
    let id: String
    let source: NotchAlertSource
    let title: String
    let badge: String?
    let symbolName: String?
    let accentHex: String?
    let bundleIdentifier: String?
    let targetURL: URL?
}

/// Unified state of the Notch panel.
enum NotchState: Equatable, Sendable {
    case idle
    case ambient([AmbientIndicator])
    case peek(NotchAlert, expanded: Bool)
}

/// Mode requested by an external NotchBridge payload.
enum BridgeMode: String, Sendable, Equatable {
    case peek
    case ambient
    case clear
}

/// Parsed payload from URL Scheme (`eave://notify?...`) or DistributedNotification.
struct BridgePayload: Equatable, Sendable {
    let id: String
    let mode: BridgeMode
    let title: String
    let subtitle: String?
    let badge: String?
    let symbolName: String?
    let accentHex: String?
    let bundleIdentifier: String?
    let targetURL: URL?
    let duration: TimeInterval

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
                // URLComponents decodes percent escapes but leaves '+' untouched from form-encoded URLs.
                let key = item.name.lowercased()
                let normalized = (key == "url") ? value : value.replacingOccurrences(of: "+", with: " ")
                return (key, normalized)
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
        let title = items["title"] ?? (mode == .clear ? "" : "Eave")
        if mode != .clear && title.isEmpty {
            return nil
        }

        let duration = items["duration"].flatMap(Double.init) ?? 4.5
        let targetURL = items["url"].flatMap(URL.init(string:))

        return BridgePayload(
            id: id,
            mode: mode,
            title: title,
            subtitle: items["subtitle"],
            badge: items["badge"],
            symbolName: items["symbol"],
            accentHex: items["accent"],
            bundleIdentifier: items["bundleid"],
            targetURL: targetURL,
            duration: max(1.5, min(duration, 30.0))
        )
    }

    /// Parses a `DistributedNotificationCenter` `userInfo` dictionary.
    static func parse(userInfo: [AnyHashable: Any]) -> BridgePayload? {
        func string(_ key: String) -> String? {
            if let value = userInfo[key] as? String, !value.isEmpty { return value }
            return nil
        }

        let modeRaw = string("mode")?.lowercased() ?? "peek"
        let mode = BridgeMode(rawValue: modeRaw) ?? .peek
        let id = string("id") ?? string("bundleID") ?? UUID().uuidString
        let title = string("title") ?? ""

        if mode != .clear && title.isEmpty {
            return nil
        }

        let duration: TimeInterval
        if let num = userInfo["duration"] as? Double {
            duration = num
        } else if let str = string("duration"), let num = Double(str) {
            duration = num
        } else {
            duration = 4.5
        }

        return BridgePayload(
            id: id,
            mode: mode,
            title: title,
            subtitle: string("subtitle"),
            badge: string("badge"),
            symbolName: string("symbol"),
            accentHex: string("accent"),
            bundleIdentifier: string("bundleID") ?? string("bundleId"),
            targetURL: string("url").flatMap(URL.init(string:)),
            duration: max(1.5, min(duration, 30.0))
        )
    }
}
