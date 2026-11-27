import Carbon.HIToolbox
import CoreGraphics
import Foundation
import XCTest
@testable import Eave

final class EaveCoreTests: XCTestCase {

    // MARK: - NotchGeometry Tests

    func testResolvePhysicalNotchGeometry() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let topLeft = CGRect(x: 0, y: 944, width: 656, height: 38)
        let topRight = CGRect(x: 856, y: 944, width: 656, height: 38)

        let geom = NotchGeometry.resolve(
            screenFrame: screen,
            safeAreaTop: 38,
            auxiliaryTopLeft: topLeft,
            auxiliaryTopRight: topRight
        )

        XCTAssertTrue(geom.isPhysicalNotch)
        XCTAssertEqual(geom.notchRect, CGRect(x: 656, y: 944, width: 200, height: 38))
        XCTAssertEqual(geom.menuBarHeight, 38)
        XCTAssertEqual(geom.topCenter, CGPoint(x: 756, y: 982))
    }

    func testResolveNonNotchedFallbackGeometry() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let geom = NotchGeometry.resolve(
            screenFrame: screen,
            safeAreaTop: 0,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil
        )

        XCTAssertFalse(geom.isPhysicalNotch)
        XCTAssertEqual(geom.notchRect.midX, 1280)
        XCTAssertEqual(geom.notchRect.width, 180)
    }

    // MARK: - NotchStateMachine Tests

    @MainActor
    func testNotchStateMachineTransitions() {
        let sm = NotchStateMachine()
        sm.enableAutoDismissTimers = false

        XCTAssertEqual(sm.state, .idle)

        let indicator = AmbientIndicator(
            id: "dock.com.example.chat",
            source: .dockBadge,
            badge: "2",
            accentHex: "#FF453A",
            bundleIdentifier: "com.example.chat"
        )
        sm.upsertAmbient(indicator)
        XCTAssertEqual(sm.state, .ambient([indicator]))

        let alert = NotchAlert(source: .dockBadge, badge: "3", bundleIdentifier: "com.example.chat")
        sm.presentPeek(alert)
        XCTAssertEqual(sm.state, .peek(alert))

        sm.setHovering(true)
        XCTAssertTrue(sm.isHovering)
        XCTAssertEqual(sm.state, .peek(alert))

        sm.dismissPeek()
        XCTAssertEqual(sm.state, .ambient([indicator]))

        sm.removeAmbient(id: indicator.id)
        XCTAssertEqual(sm.state, .idle)
    }

    // MARK: - DockBadgeDiffEngine Tests

    func testDockBadgeDiffTriggersOnlyOnNewOrIncreasedCount() {
        let watched: Set<String> = ["com.chat.app", "com.mail.app"]

        // 1. Initial badge appears -> triggers.
        let snap1 = [
            "com.chat.app": DockBadgeSnapshot(bundleIdentifier: "com.chat.app", appName: "Chat", badge: "1"),
            "com.unwatched.app": DockBadgeSnapshot(bundleIdentifier: "com.unwatched.app", appName: "Other", badge: "9")
        ]
        let diff1 = DockBadgeDiffEngine.diff(previous: [:], current: snap1, watchedBundleIDs: watched)
        XCTAssertEqual(diff1.newlyTriggered.map(\.bundleIdentifier), ["com.chat.app"])
        XCTAssertTrue(diff1.clearedBundleIDs.isEmpty)

        // 2. Count increases 1 -> 3 -> triggers.
        let snap2 = [
            "com.chat.app": DockBadgeSnapshot(bundleIdentifier: "com.chat.app", appName: "Chat", badge: "3")
        ]
        let diff2 = DockBadgeDiffEngine.diff(previous: ["com.chat.app": "1"], current: snap2, watchedBundleIDs: watched)
        XCTAssertEqual(diff2.newlyTriggered.count, 1)

        // 3. Count decreases 3 -> 2 -> should NOT trigger peek.
        let snap3 = [
            "com.chat.app": DockBadgeSnapshot(bundleIdentifier: "com.chat.app", appName: "Chat", badge: "2")
        ]
        let diff3 = DockBadgeDiffEngine.diff(previous: ["com.chat.app": "3"], current: snap3, watchedBundleIDs: watched)
        XCTAssertTrue(diff3.newlyTriggered.isEmpty)

        // 4. Badge clears -> emits clearedBundleIDs.
        let diff4 = DockBadgeDiffEngine.diff(previous: ["com.chat.app": "2"], current: [:], watchedBundleIDs: watched)
        XCTAssertTrue(diff4.newlyTriggered.isEmpty)
        XCTAssertEqual(diff4.clearedBundleIDs, ["com.chat.app"])
    }

    // MARK: - BridgePayload Parsing Tests

    func testBridgeURLParsing() throws {
        // Textless signal with custom local icon, accent hex, numeric badge, loop, and callback URL.
        let url = try XCTUnwrap(
            URL(string: "eave://notify?id=job1&icon=/tmp/my+icon.png&symbol=sparkles&accent=%2334C759&badge=12&loop=true&url=sumi://inbox&duration=999")
        )
        let payload = try XCTUnwrap(BridgePayload.parse(url: url))

        XCTAssertEqual(payload.id, "job1")
        XCTAssertEqual(payload.mode, .peek)
        XCTAssertEqual(payload.iconPath, "/tmp/my+icon.png")
        XCTAssertEqual(payload.symbolName, "sparkles")
        XCTAssertEqual(payload.accentHex, "#34C759")
        XCTAssertEqual(payload.badge, "12")
        XCTAssertTrue(payload.loop)
        XCTAssertEqual(payload.targetURL?.absoluteString, "sumi://inbox")
        XCTAssertEqual(payload.duration, 300.0) // Clamped to max 300s.

        // Non-numeric text badges are stripped so Notch never renders arbitrary text.
        let textBadgeURL = try XCTUnwrap(URL(string: "eave://notify?id=dot1&badge=OK&accent=%2338BDF8"))
        let textBadgePayload = try XCTUnwrap(BridgePayload.parse(url: textBadgeURL))
        XCTAssertNil(textBadgePayload.badge)
        XCTAssertFalse(textBadgePayload.loop)
        XCTAssertNil(textBadgePayload.duration)
        XCTAssertEqual(textBadgePayload.accentHex, "#38BDF8")

        // Numeric overflow count like "99+" is allowed; omitted badge remains nil (dot-only).
        XCTAssertEqual(BridgePayload.sanitizedNumericBadge("99+"), "99+")
        XCTAssertNil(BridgePayload.sanitizedNumericBadge("hello"))
        XCTAssertNil(BridgePayload.sanitizedNumericBadge("+"))

        // Optional activity wave style + explicit ambient expiry duration
        let waveURL = try XCTUnwrap(URL(string: "eave://notify?id=agent&mode=ambient&style=wave&symbol=sparkles&accent=%2338BDF8&duration=45"))
        let wavePayload = try XCTUnwrap(BridgePayload.parse(url: waveURL))
        XCTAssertEqual(wavePayload.mode, .ambient)
        XCTAssertEqual(wavePayload.style, .wave)
        XCTAssertEqual(wavePayload.duration, 45.0)
        XCTAssertNil(wavePayload.badge)

        let clearURL = try XCTUnwrap(URL(string: "eave://clear?id=job1"))
        let clearPayload = try XCTUnwrap(BridgePayload.parse(url: clearURL))
        XCTAssertEqual(clearPayload.mode, .clear)
        XCTAssertEqual(clearPayload.id, "job1")

        let invalidURL = try XCTUnwrap(URL(string: "https://example.com/notify?symbol=sparkles"))
        XCTAssertNil(BridgePayload.parse(url: invalidURL))
    }

    func testBridgeUserInfoParsing() throws {
        let info: [AnyHashable: Any] = [
            "id": "agent-1",
            "mode": "ambient",
            "icon": "/tmp/agent.png",
            "accent": "#38BDF8",
            "badge": 2,
            "url": "sumi://agent/1",
            "duration": 6.0
        ]
        let payload = try XCTUnwrap(BridgePayload.parse(userInfo: info))
        XCTAssertEqual(payload.mode, .ambient)
        XCTAssertEqual(payload.iconPath, "/tmp/agent.png")
        XCTAssertEqual(payload.accentHex, "#38BDF8")
        XCTAssertEqual(payload.badge, "2")
        XCTAssertEqual(payload.targetURL?.absoluteString, "sumi://agent/1")
        XCTAssertEqual(payload.duration, 6.0)
    }

    // MARK: - MenuBarSearchEngine Tests

    func testSectionClassificationAndFuzzySearch() {
        XCTAssertEqual(
            MenuBarSearchEngine.classifySection(itemMidX: 500, hiddenSeparatorX: 1100),
            .hidden
        )
        XCTAssertEqual(
            MenuBarSearchEngine.classifySection(itemMidX: 950, hiddenSeparatorX: 1100),
            .hidden
        )
        XCTAssertEqual(
            MenuBarSearchEngine.classifySection(itemMidX: 1200, hiddenSeparatorX: 1100),
            .visible
        )

        let items = [
            MenuBarItemInfo(id: "1", windowID: 1, pid: 10, bundleIdentifier: "com.tencent.xinWeChat", appName: "WeChat", title: "", frame: .zero, section: .hidden),
            MenuBarItemInfo(id: "2", windowID: 2, pid: 11, bundleIdentifier: "com.tinyspeck.slackmacgap", appName: "Slack", title: "Workspace", frame: .zero, section: .hidden),
            MenuBarItemInfo(id: "3", windowID: 3, pid: 12, bundleIdentifier: "com.apple.controlcenter", appName: "Wi-Fi", title: "Connected", frame: .zero, section: .visible)
        ]

        let fuzzy = MenuBarSearchEngine.filter(items: items, query: "wc")
        XCTAssertEqual(fuzzy.first?.appName, "WeChat")

        let prefix = MenuBarSearchEngine.filter(items: items, query: "sla")
        XCTAssertEqual(prefix.map(\.appName), ["Slack"])

        // Fuzzy character highlight offsets (substring preferred, subsequence fallback)
        XCTAssertEqual(MenuBarSearchEngine.matchedIndices(in: "Slack", query: "lac"), Set([1, 2, 3]))
        XCTAssertEqual(MenuBarSearchEngine.matchedIndices(in: "WeChat", query: "wc"), Set([0, 2]))
        XCTAssertTrue(MenuBarSearchEngine.matchedIndices(in: "Slack", query: "xyz").isEmpty)
    }

    func testNotchSurfaceMetricsConsistency() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let geom = NotchGeometry.resolve(
            screenFrame: screen,
            safeAreaTop: 38,
            auxiliaryTopLeft: CGRect(x: 0, y: 944, width: 656, height: 38),
            auxiliaryTopRight: CGRect(x: 856, y: 944, width: 656, height: 38)
        )

        let idle = NotchSurfaceMetrics.resolve(for: .idle, geometry: geom)
        XCTAssertFalse(idle.isVisible)
        XCTAssertEqual(idle.width, 200)
        XCTAssertEqual(idle.height, 38)

        let alert = NotchAlert(source: .bridge, badge: "3", symbolName: "sparkles", accentHex: "#34C759")
        let ambient = NotchSurfaceMetrics.resolve(for: .ambient([]), geometry: geom)
        let peek = NotchSurfaceMetrics.resolve(for: .peek(alert), geometry: geom)

        XCTAssertTrue(ambient.isVisible)
        XCTAssertTrue(peek.isVisible)
        XCTAssertGreaterThan(ambient.width, idle.width)
        XCTAssertGreaterThan(peek.width, ambient.width)
        // Strictly single-line hardware height (no downward text expansion).
        XCTAssertEqual(ambient.height, idle.height)
        XCTAssertEqual(peek.height, idle.height)
    }

    func testClickForwardingStrategyRouting() {
        // Regular windowed app + left click -> direct app activation (never expands menu bar).
        XCTAssertEqual(
            MenuBarClickForwarder.resolveStrategy(
                activationPolicy: .regular,
                button: .left,
                preferAppActivationForRegularApps: true
            ),
            .activateApp
        )

        // Regular windowed app + right click -> forward right click to menu bar status item.
        XCTAssertEqual(
            MenuBarClickForwarder.resolveStrategy(
                activationPolicy: .regular,
                button: .right,
                preferAppActivationForRegularApps: true
            ),
            .forwardMenuBarItem(button: .right)
        )

        // Menu-bar-only utility (accessory, e.g. Tailscale/Clash) -> forward left or right click.
        XCTAssertEqual(
            MenuBarClickForwarder.resolveStrategy(
                activationPolicy: .accessory,
                button: .left,
                preferAppActivationForRegularApps: true
            ),
            .forwardMenuBarItem(button: .left)
        )
        XCTAssertEqual(
            MenuBarClickForwarder.resolveStrategy(
                activationPolicy: .accessory,
                button: .right,
                preferAppActivationForRegularApps: true
            ),
            .forwardMenuBarItem(button: .right)
        )
    }

    @MainActor
    func testControlCenterExclusionFilter() {
        XCTAssertTrue(MenuBarItemScanner.isExcludedSystemOwner(bundleIdentifier: "com.apple.controlcenter", ownerName: "Control Center"))
        XCTAssertTrue(MenuBarItemScanner.isExcludedSystemOwner(bundleIdentifier: nil, ownerName: "Control Center"))
        XCTAssertTrue(MenuBarItemScanner.isExcludedSystemOwner(bundleIdentifier: nil, ownerName: "控制中心"))
        XCTAssertTrue(MenuBarItemScanner.isExcludedSystemOwner(bundleIdentifier: nil, ownerName: "コントロールセンター"))
        XCTAssertTrue(MenuBarItemScanner.isExcludedSystemOwner(bundleIdentifier: "com.apple.systemuiserver", ownerName: "SystemUIServer"))
        XCTAssertTrue(MenuBarItemScanner.isExcludedSystemOwner(bundleIdentifier: "com.apple.TextInputUI.xpc.CursorUIViewService", ownerName: "CursorUIViewService"))
        XCTAssertFalse(MenuBarItemScanner.isExcludedSystemOwner(bundleIdentifier: "com.tencent.xinWeChat", ownerName: "WeChat"))
        XCTAssertFalse(MenuBarItemScanner.isExcludedSystemOwner(bundleIdentifier: "io.tailscale.ipn.macsys", ownerName: "Tailscale"))
    }

    func testLocalizedControlCenterNeverLeaksAndResolvesNumericPIDProxy() {
        let apps: [MenuBarItemScanner.RunningAppSnapshot] = [
            .init(pid: 101, bundleIdentifier: "com.tencent.xinWeChat", appName: "WeChat"),
            .init(pid: 79794, bundleIdentifier: "com.abcdlsj.warren", appName: "Warren", isAccessory: true)
        ]

        // Localized Chinese Control Center ("控制中心") + unknown localized owner matched by controlCenterPIDs.
        let windows: [MenuBarItemScanner.RawStatusWindow] = [
            .init(windowID: 1, pid: 763, ownerName: "控制中心", windowName: "eave.control.hidden", bounds: CGRect(x: -3862, y: 0, width: 5004, height: 33), isOnScreen: false),
            .init(windowID: 2, pid: 763, ownerName: "控制中心", windowName: "com.tencent.xinWeChat", bounds: CGRect(x: -3950, y: 0, width: 26, height: 33), isOnScreen: false),
            // Proxy window carrying numeric PID instead of bundle ID (observed on macOS 26 Tahoe).
            .init(windowID: 3, pid: 763, ownerName: "控制中心", windowName: "79794", bounds: CGRect(x: -3910, y: 0, width: 22, height: 33), isOnScreen: false),
            // Unnamed / Item-0 / Clock / BentoBox system windows must NEVER leak as "Control Center" / "控制中心".
            .init(windowID: 4, pid: 763, ownerName: "控制中心", windowName: "Item-0", bounds: CGRect(x: -4000, y: 0, width: 24, height: 33), isOnScreen: false),
            .init(windowID: 5, pid: 763, ownerName: "控制中心", windowName: "Clock", bounds: CGRect(x: 1386, y: 0, width: 128, height: 33), isOnScreen: true),
            .init(windowID: 6, pid: 763, ownerName: "LocalizedUnknownCC", windowName: "", bounds: CGRect(x: 1356, y: 0, width: 30, height: 33), isOnScreen: true)
        ]

        let parsed = MenuBarItemScanner.parseStatusWindows(
            windows,
            runningApps: apps,
            menuBarHeight: 33,
            hiddenSeparatorX: 1142,
            excludingWindowIDs: [],
            ownPID: 999,
            ownBundleID: "com.abcdlsj.eave",
            controlCenterPIDs: [763],
            excludedSystemPIDs: [763]
        )

        XCTAssertEqual(parsed.count, 2)
        XCTAssertFalse(parsed.contains { $0.appName.contains("Control") || $0.appName.contains("控制中心") || $0.appName == "LocalizedUnknownCC" })
        let byBundle = Dictionary(uniqueKeysWithValues: parsed.compactMap { item in
            item.bundleIdentifier.map { ($0, item) }
        })
        XCTAssertEqual(byBundle["com.tencent.xinWeChat"]?.section, .hidden)
        XCTAssertEqual(byBundle["com.abcdlsj.warren"]?.section, .hidden)

        // Toggle frame extraction also works with localized Control Center owner name.
        let toggleWindows: [MenuBarItemScanner.RawStatusWindow] = [
            .init(windowID: 10, pid: 763, ownerName: "控制中心", windowName: "eave.control.toggle", bounds: CGRect(x: 1330, y: 0, width: 26, height: 33), isOnScreen: true)
        ]
        let toggleFrames = MenuBarManager.toggleFramesFromWindows(toggleWindows, primaryScreenHeight: 982, ownBundleID: "com.abcdlsj.eave")
        XCTAssertEqual(toggleFrames.count, 1)
    }

    func testMultiDisplayToggleFramesConversionAndProjection() {
        let windows: [MenuBarItemScanner.RawStatusWindow] = [
            // Built-in Retina Display (height 982, CG y=0 -> AppKit y=949)
            .init(windowID: 1, pid: 50, ownerName: "Control Center", windowName: "eave.control.toggle", bounds: CGRect(x: 1330, y: 0, width: 26, height: 33), isOnScreen: true),
            // External Screen 1 (CG y=-719, h=30 -> AppKit y=1671)
            .init(windowID: 2, pid: 50, ownerName: "Control Center", windowName: "com.abcdlsj.eave", bounds: CGRect(x: -184, y: -719, width: 26, height: 30), isOnScreen: true),
            // External Screen 2 (CG y=0, h=30 -> AppKit y=952)
            .init(windowID: 3, pid: 50, ownerName: "Control Center", windowName: "com.abcdlsj.eave", bounds: CGRect(x: 3248, y: 0, width: 26, height: 30), isOnScreen: true),
            // Collapsed hidden separator (width=5004) must NOT be treated as a toggle icon
            .init(windowID: 4, pid: 50, ownerName: "Control Center", windowName: "com.abcdlsj.eave", bounds: CGRect(x: -2037, y: 0, width: 5004, height: 30), isOnScreen: false)
        ]

        let frames = MenuBarManager.toggleFramesFromWindows(windows, primaryScreenHeight: 982, ownBundleID: "com.abcdlsj.eave")
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0], CGRect(x: 1330, y: 949, width: 26, height: 33))
        XCTAssertEqual(frames[1], CGRect(x: -184, y: 1671, width: 26, height: 30))
        XCTAssertEqual(frames[2], CGRect(x: 3248, y: 952, width: 26, height: 30))

        // Right-edge projection fallback across multiple monitors
        let screens = [
            CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: 1512, y: -98, width: 1920, height: 1080)
        ]
        let projected = MenuBarManager.projectedToggleFrames(
            from: CGRect(x: 1330, y: 949, width: 26, height: 33),
            screens: screens
        )
        XCTAssertEqual(projected.count, 2)
        XCTAssertEqual(projected[1].maxX, 3432 - (1512 - 1356), accuracy: 1.0)
    }

    func testTahoeControlCenterProxyWindowDiscoveryAndDeduplication() {
        let apps: [MenuBarItemScanner.RunningAppSnapshot] = [
            .init(pid: 101, bundleIdentifier: "com.tencent.xinWeChat", appName: "WeChat"),
            .init(pid: 102, bundleIdentifier: "io.tailscale.ipn.macsys", appName: "Tailscale"),
            .init(pid: 103, bundleIdentifier: "com.kyome.RunCat", appName: "RunCat")
        ]

        // Simulated macOS 26 Tahoe layer-25 windows across two external monitors.
        let windows: [MenuBarItemScanner.RawStatusWindow] = [
            // Screen 2 Eave collapsed separator + hidden & visible apps
            .init(windowID: 1, pid: 50, ownerName: "Control Center", windowName: "com.abcdlsj.eave", bounds: CGRect(x: -2037, y: 0, width: 5004, height: 30), isOnScreen: false),
            .init(windowID: 2, pid: 50, ownerName: "Control Center", windowName: "com.abcdlsj.eave", bounds: CGRect(x: 3248, y: 0, width: 26, height: 30), isOnScreen: true),
            .init(windowID: 3, pid: 50, ownerName: "Control Center", windowName: "com.tencent.xinWeChat", bounds: CGRect(x: -2083, y: 0, width: 26, height: 30), isOnScreen: false),
            .init(windowID: 4, pid: 50, ownerName: "Control Center", windowName: "io.tailscale.ipn.macsys", bounds: CGRect(x: -2155, y: 0, width: 26, height: 30), isOnScreen: false),
            .init(windowID: 5, pid: 50, ownerName: "Control Center", windowName: "com.kyome.RunCat", bounds: CGRect(x: 3163, y: 0, width: 32, height: 30), isOnScreen: true),
            // Duplicate proxy windows on Screen 1 (y = -719) — should be deduplicated cleanly
            .init(windowID: 6, pid: 50, ownerName: "Control Center", windowName: "com.abcdlsj.eave", bounds: CGRect(x: -5469, y: -719, width: 5004, height: 30), isOnScreen: false),
            .init(windowID: 7, pid: 50, ownerName: "Control Center", windowName: "com.tencent.xinWeChat", bounds: CGRect(x: -5515, y: -719, width: 26, height: 30), isOnScreen: false),
            .init(windowID: 8, pid: 50, ownerName: "Control Center", windowName: "com.kyome.RunCat", bounds: CGRect(x: -269, y: -719, width: 32, height: 30), isOnScreen: true),
            // System Control Center modules should remain excluded
            .init(windowID: 9, pid: 50, ownerName: "Control Center", windowName: "Clock", bounds: CGRect(x: 1386, y: 0, width: 128, height: 33), isOnScreen: true),
            .init(windowID: 10, pid: 50, ownerName: "Control Center", windowName: "BentoBox-0", bounds: CGRect(x: 1356, y: 0, width: 30, height: 33), isOnScreen: true)
        ]

        let parsed = MenuBarItemScanner.parseStatusWindows(
            windows,
            runningApps: apps,
            menuBarHeight: 33,
            hiddenSeparatorX: 1049,
            excludingWindowIDs: [],
            ownPID: 999,
            ownBundleID: "com.abcdlsj.eave"
        )

        XCTAssertEqual(parsed.count, 3)
        let byBundle = Dictionary(uniqueKeysWithValues: parsed.compactMap { item in
            item.bundleIdentifier.map { ($0, item) }
        })
        XCTAssertEqual(byBundle["com.tencent.xinWeChat"]?.section, .hidden)
        XCTAssertEqual(byBundle["io.tailscale.ipn.macsys"]?.section, .hidden)
        XCTAssertEqual(byBundle["com.kyome.RunCat"]?.section, .visible)
    }

    func testMultiMonitorNegativeXVisibleItemNotMisclassifiedAsHidden() {
        // Reproduces primary MacBook (0..1512, y=0) + external monitor on the left (-1920..0, y=-719).
        let apps: [MenuBarItemScanner.RunningAppSnapshot] = [
            .init(pid: 201, bundleIdentifier: "com.tencent.WeWorkMac", appName: "WeCom"),
            .init(pid: 202, bundleIdentifier: "com.tencent.xinWeChat", appName: "WeChat")
        ]

        let windows: [MenuBarItemScanner.RawStatusWindow] = [
            // Left external monitor Eave separator: maxX = -462
            .init(windowID: 1, pid: 50, ownerName: "Control Center", windowName: "com.abcdlsj.eave", bounds: CGRect(x: -5466, y: -719, width: 5004, height: 30), isOnScreen: false),
            // Primary monitor Eave separator: maxX = 1052
            .init(windowID: 2, pid: 50, ownerName: "Control Center", windowName: "eave.control.hidden", bounds: CGRect(x: -3952, y: 0, width: 5004, height: 33), isOnScreen: false),
            // WeCom is VISIBLE on both monitors (midX = -299.5 > -462 on left monitor; midX = 1215.5 > 1052 on primary)
            .init(windowID: 3, pid: 50, ownerName: "Control Center", windowName: "com.tencent.WeWorkMac", bounds: CGRect(x: -330, y: -719, width: 61, height: 30), isOnScreen: true),
            .init(windowID: 4, pid: 50, ownerName: "Control Center", windowName: "com.tencent.WeWorkMac", bounds: CGRect(x: 1185, y: 0, width: 61, height: 33), isOnScreen: false),
            // WeChat is HIDDEN on left monitor (midX = -5502 < -462)
            .init(windowID: 5, pid: 50, ownerName: "Control Center", windowName: "com.tencent.xinWeChat", bounds: CGRect(x: -5515, y: -719, width: 26, height: 30), isOnScreen: false)
        ]

        let bandSeps = MenuBarItemScanner.extractBandSeparators(from: windows, ownBundleID: "com.abcdlsj.eave")
        XCTAssertEqual(bandSeps.count, 2)

        // AX item reported on the left external display (negative X) must match the left display's separator (-462), NOT primary (1052).
        let axWeComFrame = CGRect(x: -330, y: -719, width: 61, height: 24)
        let resolvedSepX = MenuBarItemScanner.resolveSeparatorX(for: axWeComFrame, bandSeparators: bandSeps, fallbackHiddenSeparatorX: 1052)
        XCTAssertEqual(resolvedSepX, -462)
        XCTAssertEqual(MenuBarSearchEngine.classifySection(itemMidX: axWeComFrame.midX, hiddenSeparatorX: resolvedSepX), .visible)

        // Proxy window parsing must also keep WeCom visible and WeChat hidden.
        let parsed = MenuBarItemScanner.parseStatusWindows(
            windows,
            runningApps: apps,
            menuBarHeight: 33,
            hiddenSeparatorX: 1052,
            excludingWindowIDs: [],
            ownPID: 999,
            ownBundleID: "com.abcdlsj.eave"
        )
        let byBundle = Dictionary(uniqueKeysWithValues: parsed.compactMap { item in
            item.bundleIdentifier.map { ($0, item) }
        })
        XCTAssertEqual(byBundle["com.tencent.WeWorkMac"]?.section, .visible)
        XCTAssertEqual(byBundle["com.tencent.xinWeChat"]?.section, .hidden)
    }

    // MARK: - EaveSettings Persistence Tests

    @MainActor
    func testSettingsPersistenceAndWatchedDeduplication() {
        let suiteName = "com.abcdlsj.eave.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let s1 = EaveSettings(defaults: defaults)
        XCTAssertFalse(s1.hasCompletedOnboarding)
        XCTAssertTrue(s1.rehideAutomatically)
        XCTAssertTrue(s1.expandOnEaveHover)
        XCTAssertEqual(s1.hoverDisplayMode, .secondRow)
        XCTAssertEqual(s1.secondRowLayoutMode, .horizontalScroll)
        XCTAssertEqual(s1.secondRowItemsPerRow, EaveSettings.defaultSecondRowItemsPerRow)
        XCTAssertEqual(s1.appearanceMode, .system)
        XCTAssertTrue(s1.enableNotchPeek)
        XCTAssertEqual(s1.peekDurationSeconds, 4.5)

        s1.hasCompletedOnboarding = true
        s1.rehideAutomatically = false
        s1.expandOnEaveHover = false
        s1.hoverDelaySeconds = 0.35
        s1.hoverDisplayMode = .inline
        s1.secondRowLayoutMode = .multiRow
        s1.secondRowItemsPerRow = 6
        s1.appearanceMode = .dark
        s1.peekDurationSeconds = 6.0
        s1.addWatchedBundleID("com.example.one")
        s1.addWatchedBundleID("com.example.one")
        s1.addWatchedBundleID("  com.example.two  ")

        let s2 = EaveSettings(defaults: defaults)
        XCTAssertTrue(s2.hasCompletedOnboarding)
        XCTAssertFalse(s2.rehideAutomatically)
        XCTAssertFalse(s2.expandOnEaveHover)
        XCTAssertEqual(s2.hoverDelaySeconds, 0.35, accuracy: 0.001)
        XCTAssertEqual(s2.hoverDisplayMode, .inline)
        XCTAssertEqual(s2.secondRowLayoutMode, .multiRow)
        XCTAssertEqual(s2.secondRowItemsPerRow, 6)
        XCTAssertEqual(s2.appearanceMode, .dark)
        XCTAssertEqual(s2.peekDurationSeconds, 6.0, accuracy: 0.001)
        XCTAssertNil(AppAppearanceMode.system.nsAppearance)
        XCTAssertNotNil(AppAppearanceMode.light.nsAppearance)
        XCTAssertNotNil(AppAppearanceMode.dark.nsAppearance)
        XCTAssertNil(AppAppearanceMode.system.colorScheme)
        XCTAssertEqual(AppAppearanceMode.light.colorScheme, .light)
        XCTAssertEqual(AppAppearanceMode.dark.colorScheme, .dark)
        XCTAssertEqual(s2.watchedBundleIDs, ["com.example.one", "com.example.two"])

        // Clamping invariants for items per row
        s2.secondRowItemsPerRow = 1
        XCTAssertEqual(s2.secondRowItemsPerRow, EaveSettings.secondRowItemsPerRowRange.lowerBound)
        s2.secondRowItemsPerRow = 99
        XCTAssertEqual(s2.secondRowItemsPerRow, EaveSettings.secondRowItemsPerRowRange.upperBound)
    }

    // MARK: - Compact Divider & Second-Row Layout Tests

    @MainActor
    func testCompactSeparatorWidth() {
        XCTAssertLessThanOrEqual(MenuBarManager.expandedSeparatorLength, 12)
        XCTAssertGreaterThanOrEqual(MenuBarManager.expandedSeparatorLength, 8)
    }

    func testSecondRowChunkingAndLayoutMetrics() {
        let rows = SecondRowLayoutMetrics.chunkedRows(Array(1...10), itemsPerRow: 4)
        XCTAssertEqual(rows, [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10]])

        let empty = SecondRowLayoutMetrics.resolve(itemCount: 0, itemsPerRow: 8, layoutMode: .horizontalScroll)
        XCTAssertEqual(empty.columns, 0)
        XCTAssertEqual(empty.rows, 0)
        XCTAssertGreaterThan(empty.contentWidth, 200)

        // Horizontal scroll mode: single row bounded to itemsPerRow, horizontally scrollable when overflowing
        let hScroll = SecondRowLayoutMetrics.resolve(itemCount: 10, itemsPerRow: 5, layoutMode: .horizontalScroll)
        XCTAssertEqual(hScroll.columns, 5)
        XCTAssertEqual(hScroll.rows, 1)
        XCTAssertEqual(hScroll.visibleRows, 1)
        XCTAssertTrue(hScroll.isHorizontallyScrollable)
        XCTAssertFalse(hScroll.isVerticallyScrollable)

        let compact = SecondRowLayoutMetrics.resolve(itemCount: 3, itemsPerRow: 8, layoutMode: .horizontalScroll)
        XCTAssertEqual(compact.columns, 3)
        XCTAssertEqual(compact.rows, 1)
        XCTAssertFalse(compact.isHorizontallyScrollable)

        // Multi-row wrap mode
        let multiRow = SecondRowLayoutMetrics.resolve(itemCount: 11, itemsPerRow: 5, layoutMode: .multiRow)
        XCTAssertEqual(multiRow.columns, 5)
        XCTAssertEqual(multiRow.rows, 3)
        XCTAssertEqual(multiRow.visibleRows, 3)
        XCTAssertFalse(multiRow.isVerticallyScrollable)

        let tall = SecondRowLayoutMetrics.resolve(itemCount: 30, itemsPerRow: 5, layoutMode: .multiRow)
        XCTAssertEqual(tall.rows, 6)
        XCTAssertEqual(tall.visibleRows, SecondRowLayoutMetrics.maxVisibleRows)
        XCTAssertTrue(tall.isVerticallyScrollable)
    }

    func testSecondRowPanelFrameAnchoringAndScreenClamping() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let content = CGSize(width: 320, height: 68)

        // Anchored near right edge -> stays clamped within screen margin.
        let rightAnchor = CGRect(x: 1470, y: 944, width: 28, height: 38)
        let cardFrame = SecondRowLayoutMetrics.panelFrame(
            contentSize: content,
            anchorFrame: rightAnchor,
            screenFrame: screen,
            visibleFrame: visible,
            menuBarHeight: 38
        )
        XCTAssertLessThanOrEqual(cardFrame.maxX, visible.maxX - 12)
        XCTAssertGreaterThanOrEqual(cardFrame.minX, visible.minX + 12)
        // Visual top sits 6pt below menu bar bottom (982 - 38 - 6 = 938)
        XCTAssertEqual(cardFrame.maxY, 938, accuracy: 1.0)

        // Anchored near left edge -> clamps safely to minX + margin.
        let leftAnchor = CGRect(x: 20, y: 944, width: 28, height: 38)
        let leftFrame = SecondRowLayoutMetrics.panelFrame(
            contentSize: content,
            anchorFrame: leftAnchor,
            screenFrame: screen,
            visibleFrame: visible,
            menuBarHeight: 38
        )
        XCTAssertGreaterThanOrEqual(leftFrame.minX, visible.minX + 12)

        // Hover safe zone includes anchor, card, and the vertical bridge between them.
        let bridgePoint = CGPoint(x: rightAnchor.midX, y: 941)
        XCTAssertTrue(
            SecondRowLayoutMetrics.isPointInHoverSafeZone(
                bridgePoint,
                anchorFrame: rightAnchor,
                cardScreenFrame: cardFrame
            )
        )
        XCTAssertFalse(
            SecondRowLayoutMetrics.isPointInHoverSafeZone(
                CGPoint(x: 100, y: 100),
                anchorFrame: rightAnchor,
                cardScreenFrame: cardFrame
            )
        )
    }

    func testDockMagnificationCurve() {
        XCTAssertEqual(EaveDockMagnification.resolve(index: 2, hoveredIndex: nil), .resting)

        let primary = EaveDockMagnification.resolve(index: 2, hoveredIndex: 2)
        XCTAssertTrue(primary.isPrimary)
        XCTAssertGreaterThan(primary.scale, 1.1)
        XCTAssertLessThan(primary.liftY, 0)

        let leftNeighbor = EaveDockMagnification.resolve(index: 1, hoveredIndex: 2)
        let rightNeighbor = EaveDockMagnification.resolve(index: 3, hoveredIndex: 2)
        XCTAssertEqual(leftNeighbor, rightNeighbor)
        XCTAssertFalse(leftNeighbor.isPrimary)
        XCTAssertGreaterThan(leftNeighbor.scale, 1.0)
        XCTAssertLessThan(leftNeighbor.scale, primary.scale)

        let distant = EaveDockMagnification.resolve(index: 4, hoveredIndex: 2)
        XCTAssertEqual(distant, .resting)
    }

    // MARK: - Review Fix Regression Tests

    func testSeparatorOrderGuard() {
        let toggle = CGRect(x: 1400, y: 950, width: 24, height: 24)
        XCTAssertTrue(MenuBarManager.isSeparatorOrderValid(
            separatorFrame: CGRect(x: 1360, y: 950, width: 10, height: 24), toggleFrame: toggle))
        XCTAssertFalse(MenuBarManager.isSeparatorOrderValid(
            separatorFrame: CGRect(x: 1440, y: 950, width: 10, height: 24), toggleFrame: toggle))
        // Different displays / rows are not comparable and must never block collapsing.
        XCTAssertTrue(MenuBarManager.isSeparatorOrderValid(
            separatorFrame: CGRect(x: 1440, y: 2000, width: 10, height: 24), toggleFrame: toggle))
    }

    func testTransientUIWindowClassification() {
        let bounds = CGRect(x: 0, y: 0, width: 240, height: 300)
        XCTAssertTrue(MenuBarManager.isTransientUIWindow(layer: 101, bounds: bounds))
        XCTAssertTrue(MenuBarManager.isTransientUIWindow(layer: 3, bounds: bounds))
        XCTAssertFalse(MenuBarManager.isTransientUIWindow(layer: 0, bounds: bounds))
        XCTAssertFalse(MenuBarManager.isTransientUIWindow(layer: 25, bounds: bounds))
        XCTAssertFalse(MenuBarManager.isTransientUIWindow(layer: 101, bounds: CGRect(x: 0, y: 0, width: 2, height: 2)))
    }

    func testAXWatcherSignatureIgnoresLiveReadouts() {
        let a = MenuBarAXWatcher.signatureComponent(description: "Upload 1.2 MB/s", identifier: nil)
        let b = MenuBarAXWatcher.signatureComponent(description: "Upload 34.7 MB/s", identifier: nil)
        XCTAssertEqual(a, b)
        let quiet = MenuBarAXWatcher.signatureComponent(description: "Slack", identifier: nil)
        let unread = MenuBarAXWatcher.signatureComponent(description: "Slack, unread messages", identifier: nil)
        XCTAssertNotEqual(quiet, unread)
        XCTAssertNil(MenuBarAXWatcher.signatureComponent(description: "  ", identifier: nil))
    }

    func testHotKeyValidationAndDefaults() {
        let shiftOnly = KeyCombo(keyCode: 0, carbonModifiers: UInt32(shiftKey))
        XCTAssertFalse(shiftOnly.isValidGlobalHotKey)
        XCTAssertTrue(KeyCombo(keyCode: 0, carbonModifiers: UInt32(optionKey | shiftKey)).isValidGlobalHotKey)
        // ⌥⌘H is the system "Hide Others" shortcut and must not be Eave's default.
        let hideOthers = KeyCombo(keyCode: UInt32(kVK_ANSI_H), carbonModifiers: UInt32(optionKey | cmdKey))
        XCTAssertNotEqual(HotKeyAction.toggleHidden.defaultCombo, hideOthers)
        XCTAssertTrue(HotKeyAction.allCases.allSatisfy { $0.defaultCombo.isValidGlobalHotKey })
    }

    @MainActor
    func testClearedHotKeyStaysClearedAcrossLaunches() {
        let suiteName = "com.abcdlsj.eave.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let s1 = EaveSettings(defaults: defaults)
        XCTAssertNotNil(s1.hotKey(for: .openSearch))
        s1.setHotKey(nil, for: .openSearch)
        XCTAssertNil(EaveSettings(defaults: defaults).hotKey(for: .openSearch))

        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_J), carbonModifiers: UInt32(controlKey | optionKey))
        s1.setHotKey(combo, for: .openSearch)
        XCTAssertEqual(EaveSettings(defaults: defaults).hotKey(for: .openSearch), combo)
    }

    @MainActor
    func testNotchStateMachineResetsHoverAndCapsAmbient() {
        let sm = NotchStateMachine()
        sm.enableAutoDismissTimers = false

        sm.presentPeek(NotchAlert(source: .system, badge: "1"))
        sm.setHovering(true)
        sm.dismissPeek()
        XCTAssertFalse(sm.isHovering, "Clicking the notch must not leave a stale hover flag behind")

        for i in 0..<(NotchStateMachine.maxAmbientIndicators + 5) {
            sm.upsertAmbient(AmbientIndicator(id: "bridge.\(i)", source: .bridge))
        }
        XCTAssertEqual(sm.ambientIndicators.count, NotchStateMachine.maxAmbientIndicators)
        XCTAssertEqual(sm.ambientIndicators.first?.id, "bridge.5")
    }

    func testProtectedMenuBarRegionGeometry() {
        // Built-in notched MacBook display: notch sits at x 656..856, auxiliaryTopRight is 856..1512.
        let primaryScreen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let auxRight = CGRect(x: 856, y: 944, width: 656, height: 38)
        let primarySep = CGRect(x: 1250, y: 944, width: 10, height: 38)
        let primaryToggle = CGRect(x: 1330, y: 944, width: 26, height: 38)

        func checkPrimary(_ pt: CGPoint) -> Bool {
            MenuBarManager.isPointInProtectedMenuBarRegion(
                point: pt,
                screenFrame: primaryScreen,
                menuBarHeight: 38,
                auxiliaryTopRightArea: auxRight,
                separatorFrameOnScreen: primarySep,
                toggleFrameOnScreen: primaryToggle,
                primarySeparatorFrame: primarySep,
                primaryToggleFrame: primaryToggle
            )
        }

        // Hidden section icons & `•` divider & topmost pixel row are protected.
        XCTAssertTrue(checkPrimary(CGPoint(x: 1100, y: 960)))
        XCTAssertTrue(checkPrimary(CGPoint(x: 1100, y: 982)))
        XCTAssertTrue(checkPrimary(CGPoint(x: 1255, y: 960)))
        // Resting on Eave's own toggle icon is protected.
        XCTAssertTrue(checkPrimary(CGPoint(x: 1340, y: 960)))
        // Visible icons between `•` and Eave, Clock/Control Center, left App menus, and content below bar are NOT protected.
        XCTAssertFalse(checkPrimary(CGPoint(x: 1295, y: 960)))
        XCTAssertFalse(checkPrimary(CGPoint(x: 1450, y: 960)))
        XCTAssertFalse(checkPrimary(CGPoint(x: 120, y: 960)))
        XCTAssertFalse(checkPrimary(CGPoint(x: 1100, y: 800)))

        // External non-notched monitor on the right: separator X is projected from primary visible width (1356 - 1260 = 96pt).
        let externalScreen = CGRect(x: 1512, y: -98, width: 1920, height: 1080)
        let externalToggle = CGRect(x: 3250, y: 952, width: 26, height: 30)
        // Projected separator maxX = 3276 - 96 = 3180.
        func checkExternal(_ pt: CGPoint) -> Bool {
            MenuBarManager.isPointInProtectedMenuBarRegion(
                point: pt,
                screenFrame: externalScreen,
                menuBarHeight: 30,
                auxiliaryTopRightArea: nil,
                separatorFrameOnScreen: nil,
                toggleFrameOnScreen: externalToggle,
                primarySeparatorFrame: primarySep,
                primaryToggleFrame: primaryToggle
            )
        }

        XCTAssertTrue(checkExternal(CGPoint(x: 3000, y: 965)))
        XCTAssertTrue(checkExternal(CGPoint(x: 3260, y: 965)))
        XCTAssertFalse(checkExternal(CGPoint(x: 3215, y: 965)))
        XCTAssertFalse(checkExternal(CGPoint(x: 3380, y: 965)))
    }

    func testMenuBarPopoverAndMenuWindowClassification() {
        let ownPID: pid_t = 999
        let otherPID: pid_t = 123
        let screenCGTop: CGFloat = 0
        let menuBarHeight: CGFloat = 38

        // Dropdown NSMenu (layer 101) below menu bar -> protected.
        XCTAssertTrue(MenuBarManager.isMenuBarPopoverOrMenuWindow(
            layer: Int(CGWindowLevelForKey(.popUpMenuWindow)),
            bounds: CGRect(x: 1050, y: 38, width: 220, height: 280),
            ownerPID: otherPID,
            ownPID: ownPID,
            screenCGTop: screenCGTop,
            menuBarHeight: menuBarHeight
        ))

        // Anchored popover / MenuBarExtra panel (layer 3 or statusWindow) directly below menu bar -> protected.
        XCTAssertTrue(MenuBarManager.isMenuBarPopoverOrMenuWindow(
            layer: Int(CGWindowLevelForKey(.floatingWindow)),
            bounds: CGRect(x: 1020, y: 42, width: 320, height: 420),
            ownerPID: otherPID,
            ownPID: ownPID,
            screenCGTop: screenCGTop,
            menuBarHeight: menuBarHeight
        ))
        XCTAssertTrue(MenuBarManager.isMenuBarPopoverOrMenuWindow(
            layer: Int(CGWindowLevelForKey(.statusWindow)),
            bounds: CGRect(x: 1020, y: 40, width: 300, height: 260),
            ownerPID: otherPID,
            ownPID: ownPID,
            screenCGTop: screenCGTop,
            menuBarHeight: menuBarHeight
        ))

        // Status item icon window strictly inside the menu bar band -> excluded.
        XCTAssertFalse(MenuBarManager.isMenuBarPopoverOrMenuWindow(
            layer: Int(CGWindowLevelForKey(.statusWindow)),
            bounds: CGRect(x: 1100, y: 0, width: 28, height: 38),
            ownerPID: otherPID,
            ownPID: ownPID,
            screenCGTop: screenCGTop,
            menuBarHeight: menuBarHeight
        ))

        // Normal document window (layer 0), Dock (layer 20), own windows, and unrelated bottom PiP -> excluded.
        XCTAssertFalse(MenuBarManager.isMenuBarPopoverOrMenuWindow(
            layer: 0,
            bounds: CGRect(x: 200, y: 38, width: 900, height: 700),
            ownerPID: otherPID,
            ownPID: ownPID,
            screenCGTop: screenCGTop,
            menuBarHeight: menuBarHeight
        ))
        XCTAssertFalse(MenuBarManager.isMenuBarPopoverOrMenuWindow(
            layer: Int(CGWindowLevelForKey(.dockWindow)),
            bounds: CGRect(x: 400, y: 910, width: 700, height: 72),
            ownerPID: otherPID,
            ownPID: ownPID,
            screenCGTop: screenCGTop,
            menuBarHeight: menuBarHeight
        ))
        XCTAssertFalse(MenuBarManager.isMenuBarPopoverOrMenuWindow(
            layer: Int(CGWindowLevelForKey(.popUpMenuWindow)),
            bounds: CGRect(x: 1050, y: 38, width: 220, height: 280),
            ownerPID: ownPID,
            ownPID: ownPID,
            screenCGTop: screenCGTop,
            menuBarHeight: menuBarHeight
        ))
        XCTAssertFalse(MenuBarManager.isMenuBarPopoverOrMenuWindow(
            layer: Int(CGWindowLevelForKey(.floatingWindow)),
            bounds: CGRect(x: 1100, y: 600, width: 320, height: 180),
            ownerPID: otherPID,
            ownPID: ownPID,
            screenCGTop: screenCGTop,
            menuBarHeight: menuBarHeight
        ))
        XCTAssertFalse(MenuBarManager.isMenuBarPopoverOrMenuWindow(
            layer: Int(CGWindowLevelForKey(.popUpMenuWindow)),
            bounds: CGRect(x: 1050, y: 38, width: 220, height: 280),
            alpha: 0.0,
            ownerPID: otherPID,
            ownPID: ownPID,
            screenCGTop: screenCGTop,
            menuBarHeight: menuBarHeight
        ))
    }
}
