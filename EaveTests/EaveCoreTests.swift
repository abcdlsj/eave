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
            title: "Chat",
            badge: "2",
            symbolName: nil,
            accentHex: "#EF4444",
            bundleIdentifier: "com.example.chat",
            targetURL: nil
        )
        sm.upsertAmbient(indicator)
        XCTAssertEqual(sm.state, .ambient([indicator]))

        let alert = NotchAlert(source: .dockBadge, title: "Chat", badge: "3")
        sm.presentPeek(alert)
        XCTAssertEqual(sm.state, .peek(alert, expanded: false))

        sm.setHovering(true)
        XCTAssertEqual(sm.state, .peek(alert, expanded: true))

        sm.dismissPeek()
        XCTAssertEqual(sm.state, .ambient([indicator]))

        // Opening bar queues alerts arriving while bar is active.
        sm.openBar()
        XCTAssertEqual(sm.state, .bar)

        let queuedAlert = NotchAlert(source: .bridge, title: "Build Done", badge: "OK")
        sm.presentPeek(queuedAlert)
        XCTAssertEqual(sm.state, .bar)

        sm.closeBar()
        XCTAssertEqual(sm.state, .peek(queuedAlert, expanded: false))

        sm.dismissPeek()
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
        let url = try XCTUnwrap(
            URL(string: "eave://notify?id=job1&title=Deploy+Done&subtitle=prod&badge=OK&symbol=sparkles&duration=99")
        )
        let payload = try XCTUnwrap(BridgePayload.parse(url: url))

        XCTAssertEqual(payload.id, "job1")
        XCTAssertEqual(payload.mode, .peek)
        XCTAssertEqual(payload.title, "Deploy Done")
        XCTAssertEqual(payload.subtitle, "prod")
        XCTAssertEqual(payload.badge, "OK")
        XCTAssertEqual(payload.symbolName, "sparkles")
        XCTAssertEqual(payload.duration, 30.0) // Clamped to max 30s.

        let clearURL = try XCTUnwrap(URL(string: "eave://clear?id=job1"))
        let clearPayload = try XCTUnwrap(BridgePayload.parse(url: clearURL))
        XCTAssertEqual(clearPayload.mode, .clear)
        XCTAssertEqual(clearPayload.id, "job1")

        let invalidURL = try XCTUnwrap(URL(string: "https://example.com/notify?title=Nope"))
        XCTAssertNil(BridgePayload.parse(url: invalidURL))
    }

    func testBridgeUserInfoParsing() throws {
        let info: [AnyHashable: Any] = [
            "id": "agent-1",
            "mode": "ambient",
            "title": "Agent Active",
            "badge": "2",
            "duration": 6.0
        ]
        let payload = try XCTUnwrap(BridgePayload.parse(userInfo: info))
        XCTAssertEqual(payload.mode, .ambient)
        XCTAssertEqual(payload.title, "Agent Active")
        XCTAssertEqual(payload.badge, "2")
        XCTAssertEqual(payload.duration, 6.0)
    }

    // MARK: - MenuBarSearchEngine Tests

    func testSectionClassificationAndFuzzySearch() {
        XCTAssertEqual(
            MenuBarSearchEngine.classifySection(itemMidX: 500, hiddenSeparatorX: 1100, alwaysHiddenSeparatorX: 800),
            .alwaysHidden
        )
        XCTAssertEqual(
            MenuBarSearchEngine.classifySection(itemMidX: 950, hiddenSeparatorX: 1100, alwaysHiddenSeparatorX: 800),
            .hidden
        )
        XCTAssertEqual(
            MenuBarSearchEngine.classifySection(itemMidX: 1200, hiddenSeparatorX: 1100, alwaysHiddenSeparatorX: 800),
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
    }

    // MARK: - EaveSettings Persistence Tests

    @MainActor
    func testSettingsPersistenceAndWatchedDeduplication() {
        let suiteName = "com.abcdlsj.eave.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let s1 = EaveSettings(defaults: defaults)
        s1.rehideDelaySeconds = 12
        s1.addWatchedBundleID("com.example.one")
        s1.addWatchedBundleID("com.example.one")
        s1.addWatchedBundleID("  com.example.two  ")

        let s2 = EaveSettings(defaults: defaults)
        XCTAssertEqual(s2.rehideDelaySeconds, 12)
        XCTAssertEqual(s2.watchedBundleIDs, ["com.example.one", "com.example.two"])
    }
}
