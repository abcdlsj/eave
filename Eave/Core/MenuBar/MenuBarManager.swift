import AppKit
import Foundation
import Observation

/// Phase 1 core: manages the three-section menu bar layout (Visible / Hidden / Always-Hidden)
/// using standard NSStatusItem separator length inflation — zero private APIs, zero permissions required.
@MainActor
@Observable
final class MenuBarManager: NSObject {
    private static let collapsedSeparatorLength: CGFloat = 10_000
    /// Compact divider slot width so the separator sits tightly between Visible and Hidden items
    /// without leaving excessive empty horizontal padding in the menu bar.
    static let expandedSeparatorLength: CGFloat = 10

    private let settings: EaveSettings

    // Rightmost visible anchor icon (minimalist Eave glyph).
    private var toggleItem: NSStatusItem!
    // Lightweight pass-through tracking view attached to the Eave toggle button for instant hover detection.
    private var toggleHoverView: StatusItemHoverView?
    // Separator between Visible and Hidden sections.
    private var hiddenSeparator: NSStatusItem!
    // Optional separator between Hidden and Always-Hidden sections.
    private var alwaysHiddenSeparator: NSStatusItem?

    private var rehideTimer: Timer?
    private var appSwitchObserver: Any?
    private var screenParamsObserver: Any?
    private var activeSpaceObserver: Any?
    private var cachedMultiDisplayToggleFrames: [CGRect] = []

    private(set) var isHiddenExpanded: Bool = false
    private(set) var isAlwaysHiddenExpanded: Bool = false
    private(set) var isContextMenuOpen: Bool = false

    /// Callbacks wired by AppCoordinator for cross-module orchestration.
    var onRequestNotchBarToggle: (() -> Void)?
    var onRequestOpenSearch: (() -> Void)?
    var onRequestOpenSettings: (() -> Void)?
    var onRequestTestPeek: (() -> Void)?
    var onExpansionChanged: ((Bool, Bool) -> Void)?
    var onToggleHoverChanged: ((Bool) -> Void)?
    var onWillHandleToggleInteraction: (() -> Void)?
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
        if let observer = screenParamsObserver {
            NotificationCenter.default.removeObserver(observer)
            screenParamsObserver = nil
        }
        if let observer = activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activeSpaceObserver = nil
        }
        toggleHoverView?.removeFromSuperview()
        toggleHoverView = nil
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

    // MARK: - Separator Coordinates (Used by Phase 3 Scanner & Multi-Display Hover Bar)

    /// Screen-space frame of Eave's primary toggle status item button (AppKit global coordinates).
    var toggleItemFrame: CGRect? {
        toggleItem.button?.window?.frame
    }

    /// Screen-space frames of Eave's toggle status item across ALL connected displays (AppKit global coordinates).
    /// On multi-monitor macOS setups, `NSStatusItem.button?.window` only covers one display while Control Center
    /// renders mirror toggle items on every other display.
    var allToggleItemFrames: [CGRect] {
        var frames = cachedMultiDisplayToggleFrames
        if let primaryFrame = toggleItemFrame, primaryFrame.width > 0, primaryFrame.height > 0 {
            let alreadyPresent = frames.contains { existing in
                abs(existing.midX - primaryFrame.midX) < 12 && abs(existing.midY - primaryFrame.midY) < 12
            }
            if !alreadyPresent {
                frames.insert(primaryFrame, at: 0)
            }
        }

        // If any display still lacks a cached frame (e.g., before first window-list refresh),
        // project the right-edge offset from the primary toggle frame so hover works immediately on all monitors.
        let screenFrames = NSScreen.screens.map(\.frame)
        if let anchor = frames.first, screenFrames.count > frames.count {
            let projected = Self.projectedToggleFrames(from: anchor, screens: screenFrames)
            for candidate in projected {
                let exists = frames.contains { existing in
                    abs(existing.midX - candidate.midX) < 24 && abs(existing.midY - candidate.midY) < 24
                }
                if !exists {
                    frames.append(candidate)
                }
            }
        }
        return frames
    }

    /// Returns the Eave toggle icon frame on the display containing `point` (falling back to nearest/primary).
    func toggleItemFrame(near point: CGPoint) -> CGRect? {
        let frames = allToggleItemFrames
        if let exact = frames.first(where: { $0.insetBy(dx: -4, dy: -4).contains(point) }) {
            return exact
        }
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            if let onScreen = frames.first(where: { screen.frame.contains(CGPoint(x: $0.midX, y: $0.midY)) }) {
                return onScreen
            }
        }
        return frames.first ?? toggleItemFrame
    }

    /// Refreshes cached multi-display Eave toggle button frames off-main using WindowServer layer-25 proxy windows.
    func refreshToggleFramesCache() {
        let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? 982
        let ownBundleID = Bundle.main.bundleIdentifier?.lowercased() ?? "com.abcdlsj.eave"

        Task { [weak self] in
            let frames = await Task.detached(priority: .utility) {
                let raw = MenuBarItemScanner.fetchRawStatusWindows()
                return Self.toggleFramesFromWindows(
                    raw,
                    primaryScreenHeight: primaryHeight,
                    ownBundleID: ownBundleID
                )
            }.value
            guard let self else { return }
            if !frames.isEmpty {
                self.cachedMultiDisplayToggleFrames = frames
            }
        }
    }

    /// Pure converter extracting AppKit global frames of all on-screen Eave toggle icons across displays.
    nonisolated static func toggleFramesFromWindows(
        _ rawWindows: [MenuBarItemScanner.RawStatusWindow],
        primaryScreenHeight: CGFloat,
        ownBundleID: String = "com.abcdlsj.eave"
    ) -> [CGRect] {
        let lowerOwn = ownBundleID.lowercased()
        var results: [CGRect] = []

        for win in rawWindows {
            guard win.isOnScreen else { continue }
            guard win.bounds.width >= 12, win.bounds.width <= 80,
                  win.bounds.height >= 16, win.bounds.height <= 64 else {
                continue
            }
            let lowerOwner = win.ownerName.lowercased()
            let lowerName = win.windowName.lowercased()
            let isToggle = (lowerOwner == "control center" && (lowerName == "eave.control.toggle" || lowerName == lowerOwn))
                || lowerName == "eave.control.toggle"
            guard isToggle else { continue }

            // Convert CoreGraphics top-left coordinates to AppKit bottom-left coordinates.
            let appKitY = primaryScreenHeight - win.bounds.maxY
            let converted = CGRect(
                x: win.bounds.minX,
                y: appKitY,
                width: win.bounds.width,
                height: win.bounds.height
            )
            let duplicate = results.contains {
                abs($0.midX - converted.midX) < 8 && abs($0.midY - converted.midY) < 8
            }
            if !duplicate {
                results.append(converted)
            }
        }

        return results
    }

    /// Projects a known toggle icon's right-edge offset onto other connected displays as a fast fallback.
    nonisolated static func projectedToggleFrames(from knownFrame: CGRect, screens: [CGRect]) -> [CGRect] {
        guard let sourceScreen = screens.first(where: { $0.contains(CGPoint(x: knownFrame.midX, y: knownFrame.midY)) }) else {
            return [knownFrame]
        }
        let rightOffset = sourceScreen.maxX - knownFrame.maxX
        guard rightOffset >= 0 else { return [knownFrame] }

        return screens.map { screen in
            if screen == sourceScreen {
                return knownFrame
            }
            let height = min(knownFrame.height, 34)
            return CGRect(
                x: screen.maxX - rightOffset - knownFrame.width,
                y: screen.maxY - height,
                width: knownFrame.width,
                height: height
            )
        }
    }

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
        configureSeparatorButton(
            hiddenSeparator,
            image: Self.makeDividerImage(style: .dot),
            tooltip: "Eave Hidden Section Divider (⌘-drag icons left to hide)"
        )

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
        // Place Always-Hidden far to the left when opted in so it never traps normal icons.
        if defaults.object(forKey: alwaysKey) == nil {
            defaults.set(1200.0, forKey: alwaysKey)
        }
    }

    private func ensureAlwaysHiddenSeparator() {
        guard alwaysHiddenSeparator == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: Self.collapsedSeparatorLength)
        item.autosaveName = "eave.control.alwaysHidden"
        configureSeparatorButton(
            item,
            image: Self.makeDividerImage(style: .doubleDot),
            tooltip: "Eave Always-Hidden Divider (⌘-drag icons left to keep hidden)"
        )
        alwaysHiddenSeparator = item
    }

    private enum DividerStyle {
        case dot
        case doubleDot
    }

    /// Renders a crisp, ultra-compact template divider glyph harmonized with macOS menu bar aesthetics.
    /// A precision centered dot (`•`) cleanly separates Visible and Hidden items without the clutter
    /// or ambiguity of a pipe (`|`), while double-dot (`:`) marks the Always-Hidden boundary.
    private static func makeDividerImage(style: DividerStyle) -> NSImage {
        let size = NSSize(width: 8, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            switch style {
            case .dot:
                let diameter: CGFloat = 4.0
                let dotRect = NSRect(
                    x: (rect.width - diameter) / 2,
                    y: (rect.height - diameter) / 2,
                    width: diameter,
                    height: diameter
                )
                NSBezierPath(ovalIn: dotRect).fill()

            case .doubleDot:
                let dot: CGFloat = 2.6
                let gap: CGFloat = 2.8
                let cx = (rect.width - dot) / 2
                let cy = rect.height / 2
                let topRect = NSRect(x: cx, y: cy + gap / 2, width: dot, height: dot)
                let botRect = NSRect(x: cx, y: cy - gap / 2 - dot, width: dot, height: dot)
                NSBezierPath(ovalIn: topRect).fill()
                NSBezierPath(ovalIn: botRect).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
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
        // Intentionally omit system toolTip so native macOS tooltip popups never collide with Eave's hover reveal.
        button.toolTip = nil
        button.setAccessibilityLabel("Eave")
        button.target = self
        button.action = #selector(handleToggleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let hoverView = StatusItemHoverView(frame: button.bounds)
        hoverView.autoresizingMask = [.width, .height]
        hoverView.onHoverChanged = { [weak self] hovering in
            self?.onToggleHoverChanged?(hovering)
        }
        button.addSubview(hoverView)
        toggleHoverView = hoverView
    }

    private func configureSeparatorButton(_ item: NSStatusItem, image: NSImage, tooltip: String) {
        guard let button = item.button else { return }
        button.image = image
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.alphaValue = 0.72
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

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            toggleItem.button?.animator().alphaValue = isHiddenExpanded ? 1.0 : 0.85
        }
    }

    // MARK: - Actions & Context Menu

    @objc private func handleToggleClick(_ sender: NSStatusBarButton) {
        onWillHandleToggleInteraction?()

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

        func makeItem(title: String, symbol: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
            item.target = self
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            return item
        }

        let toggleTitle = isHiddenExpanded ? "Hide Menu Bar Items" : "Show Hidden Items"
        let toggleSymbol = isHiddenExpanded ? "eye.slash" : "eye"
        menu.addItem(makeItem(title: toggleTitle, symbol: toggleSymbol, action: #selector(menuToggleHidden)))

        if settings.enableAlwaysHiddenSection {
            let alwaysTitle = isAlwaysHiddenExpanded ? "Hide Always-Hidden Items" : "Show Always-Hidden Items"
            let alwaysSymbol = isAlwaysHiddenExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical"
            menu.addItem(makeItem(title: alwaysTitle, symbol: alwaysSymbol, action: #selector(menuToggleAlwaysHidden)))
        }

        menu.addItem(makeItem(title: "Toggle Notch Bar", symbol: "macbook", action: #selector(menuToggleNotchBar)))
        menu.addItem(makeItem(title: "Search Menu Bar...", symbol: "magnifyingglass", action: #selector(menuOpenSearch)))

        menu.addItem(.separator())

        menu.addItem(makeItem(title: "Preview Notch Peek", symbol: "bell.badge", action: #selector(menuTestPeek)))
        menu.addItem(makeItem(title: "Settings...", symbol: "gearshape", action: #selector(menuOpenSettings), keyEquivalent: ","))

        menu.addItem(.separator())

        menu.addItem(makeItem(title: "Quit Eave", symbol: "power", action: #selector(menuQuit), keyEquivalent: "q"))

        isContextMenuOpen = true
        defer { isContextMenuOpen = false }
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

        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshToggleFramesCache()
            }
        }

        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshToggleFramesCache()
            }
        }

        refreshToggleFramesCache()
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

/// Pass-through `NSView` overlay installed on the Eave `NSStatusBarButton` for zero-CPU native hover tracking.
@MainActor
private final class StatusItemHoverView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Never intercept left/right clicks or ⌘-drags on the underlying status bar button.
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChanged?(false)
    }
}
