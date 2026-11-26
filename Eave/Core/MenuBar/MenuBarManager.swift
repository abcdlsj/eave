import AppKit
import Foundation
import Observation

/// Manages Eave's two-section menu bar layout (Visible / Hidden)
/// using standard NSStatusItem separator length inflation — zero private APIs, zero permissions required.
@MainActor
@Observable
final class MenuBarManager: NSObject {
    private static let collapsedSeparatorLength: CGFloat = 10_000
    /// Compact divider slot width so the separator sits tightly between Visible and Hidden items
    /// without leaving excessive empty horizontal padding in the menu bar.
    static let expandedSeparatorLength: CGFloat = 10
    private static let transientForwardRehideSeconds: TimeInterval = 4.0
    /// How long the pointer may stay outside the menu bar before a hover-only reveal collapses again.
    private static let hoverLeaveGraceSeconds: TimeInterval = 0.45
    /// Window after a click in the menu bar during which app-activation must not collapse revealed items
    /// (clicking a revealed item often activates its owning app).
    private static let recentMenuBarClickSeconds: TimeInterval = 1.5

    /// Why the hidden section is currently expanded. Drives which dismissal rules apply.
    enum ExpansionSource: Equatable {
        /// Collapsed.
        case none
        /// Explicit user intent (click, hotkey, menu): stays until click-away, app switch, or auto-rehide.
        case user
        /// Hover-only reveal: collapses as soon as the pointer leaves the menu bar, unless the user interacts.
        case hover
        /// Briefly expanded to anchor a forwarded click on a hidden item.
        case transientForward
    }

    private let settings: EaveSettings

    // Rightmost visible anchor icon (minimalist Eave glyph).
    private var toggleItem: NSStatusItem!
    // Lightweight pass-through tracking view attached to the Eave toggle button for instant hover detection.
    private var toggleHoverView: StatusItemHoverView?
    // Separator between Visible and Hidden sections.
    private var hiddenSeparator: NSStatusItem!

    private var rehideTimer: Timer?
    private var appSwitchObserver: Any?
    private var screenParamsObserver: Any?
    private var activeSpaceObserver: Any?
    private var cachedMultiDisplayToggleFrames: [CGRect] = []

    private var hoverLeaveTimer: Timer?
    private var dragEndValidationTask: Task<Void, Never>?
    private var lastMenuBarClickTime: CFAbsoluteTime = 0
    /// Set once the pointer leaves the Eave icon after a hover reveal; a click before that pins the reveal.
    private var pointerLeftToggleSinceHoverReveal = false

    private(set) var isHiddenExpanded: Bool = false
    private(set) var expansionSource: ExpansionSource = .none
    /// True when the menu bar was temporarily expanded solely to anchor a forwarded menu-bar-only app click.
    var isTransientForwardExpansion: Bool { isHiddenExpanded && expansionSource == .transientForward }
    /// True while the hidden section is shown only because the pointer hovered the Eave icon.
    var isHoverExpansion: Bool { isHiddenExpanded && expansionSource == .hover }
    private(set) var isContextMenuOpen: Bool = false

    /// Callbacks wired by AppCoordinator for cross-module orchestration.
    var onRequestOpenSearch: (() -> Void)?
    var onRequestOpenSettings: (() -> Void)?
    var onRequestTestPeek: (() -> Void)?
    var onExpansionChanged: ((Bool) -> Void)?
    var onToggleHoverChanged: ((Bool) -> Void)?
    var onWillHandleToggleInteraction: (() -> Void)?
    var isPointerProtectedFromRehide: (() -> Bool)?

    init(settings: EaveSettings) {
        self.settings = settings
        super.init()
        setupStatusItems()
        observeWorkspace()
        // A divider left right of the icon by an earlier ⌘-drag would hide the Eave icon from launch on.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self?.repairControlOrderIfNeeded()
        }
    }

    func tearDown() {
        rehideTimer?.invalidate()
        rehideTimer = nil
        hoverLeaveTimer?.invalidate()
        hoverLeaveTimer = nil
        dragEndValidationTask?.cancel()
        dragEndValidationTask = nil
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
    }

    // MARK: - Public Controls

    func toggleHidden() {
        if isHiddenExpanded {
            collapseAll()
        } else {
            expandHidden()
        }
    }

    func expandHidden() {
        expand(source: .user)
    }

    /// Reveals hidden items because the pointer is resting on the Eave icon.
    /// The reveal is transient: it collapses once the pointer leaves the menu bar unless the user interacts.
    func expandFromHover() {
        guard !isHiddenExpanded else { return }
        pointerLeftToggleSinceHoverReveal = false
        expand(source: .hover)
    }

    /// Briefly reveals the hidden section so a menu-bar-only popover/menu can anchor at the top-right,
    /// then collapses immediately once interaction ends.
    func expandTemporarilyForForwarding() {
        expand(source: .transientForward)
    }

    private func expand(source: ExpansionSource) {
        let wasExpanded = isHiddenExpanded
        expansionSource = source
        isHiddenExpanded = true
        hoverLeaveTimer?.invalidate()
        hoverLeaveTimer = nil
        applySeparatorLengths()
        scheduleAutoRehideIfNeeded()
        if !wasExpanded {
            onExpansionChanged?(true)
        }
    }

    /// Converts a hover-only reveal into a regular one (the user clicked into the revealed menu bar,
    /// so its menus must not vanish when the pointer moves down into them).
    func promoteHoverExpansionToUser() {
        guard isHoverExpansion else { return }
        expansionSource = .user
        hoverLeaveTimer?.invalidate()
        hoverLeaveTimer = nil
        scheduleAutoRehideIfNeeded()
    }

    /// Called by the event monitor when the pointer leaves the Eave icon.
    func notePointerLeftToggle() {
        pointerLeftToggleSinceHoverReveal = true
    }

    /// Any mouse-down inside the menu bar (on any display).
    func noteMenuBarClick(at point: CGPoint) {
        lastMenuBarClickTime = CFAbsoluteTimeGetCurrent()
        // A click on the Eave icon itself is handled by `handleToggleClick` (which pins a hover reveal);
        // on systems where the global monitor also sees that click, promoting here would make it collapse.
        let onToggle = allToggleItemFrames.contains { $0.insetBy(dx: -3, dy: -3).contains(point) }
        guard !onToggle else { return }
        promoteHoverExpansionToUser()
    }

    /// Any mouse-up anywhere. Used to re-validate Eave's control item order after a ⌘-drag in the menu bar.
    func noteMouseUp(inMenuBar: Bool, commandHeld: Bool) {
        guard inMenuBar || commandHeld else { return }
        dragEndValidationTask?.cancel()
        dragEndValidationTask = Task { [weak self] in
            // Let the status bar settle the dropped item before reading frames.
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled else { return }
            self.repairControlOrderIfNeeded()
            self.refreshToggleFramesCache()
            if self.isHiddenExpanded {
                self.scheduleAutoRehideIfNeeded()
            }
        }
    }

    /// Hover-reveal dismissal: collapses shortly after the pointer leaves the menu bar band.
    func handlePointerMoved(to point: CGPoint) {
        guard isHoverExpansion else {
            hoverLeaveTimer?.invalidate()
            hoverLeaveTimer = nil
            return
        }
        if Self.isPointInMenuBar(point) {
            hoverLeaveTimer?.invalidate()
            hoverLeaveTimer = nil
            return
        }
        guard hoverLeaveTimer == nil else { return }
        hoverLeaveTimer = Timer.scheduledTimer(withTimeInterval: Self.hoverLeaveGraceSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.hoverLeaveTimer = nil
                guard self.isHoverExpansion else { return }
                if Self.isPointInMenuBar(NSEvent.mouseLocation) { return }
                if self.isInteractionInProgress() { 
                    // Re-arm: keep checking until the drag/menu finishes.
                    self.handlePointerMoved(to: NSEvent.mouseLocation)
                    return
                }
                if self.isPointerProtectedFromRehide?() == true { return }
                self.collapseAll()
            }
        }
    }

    func collapseIfTransient() {
        guard isTransientForwardExpansion else { return }
        collapseAll()
    }

    func collapseAll() {
        guard isHiddenExpanded else { return }
        rehideTimer?.invalidate()
        rehideTimer = nil
        hoverLeaveTimer?.invalidate()
        hoverLeaveTimer = nil
        // If the user ⌘-dragged the divider to the right of the Eave icon (or the icon left of the divider),
        // collapsing would push the Eave icon itself off-screen. Repair the order first.
        repairControlOrderIfNeeded()
        isHiddenExpanded = false
        expansionSource = .none
        applySeparatorLengths()
        onExpansionChanged?(false)
    }

    /// True while a mouse button is held (⌘-dragging an icon) or a menu from any app is open.
    /// Collapsing then would yank the separator mid-drag or orphan the open menu.
    func isInteractionInProgress() -> Bool {
        if NSEvent.pressedMouseButtons != 0 { return true }
        return Self.isAnyMenuOpenOnScreen()
    }

    /// Resets the auto-rehide countdown (for example while the user interacts with expanded items).
    func postponeAutoRehide() {
        guard isHiddenExpanded else { return }
        scheduleAutoRehideIfNeeded()
    }

    // MARK: - Separator Coordinates (Used by Scanner & Multi-Display Hover Bar)

    /// Screen-space frame of Eave's primary toggle status item button (AppKit global coordinates).
    var toggleItemFrame: CGRect? {
        toggleItem.button?.window?.frame
    }

    /// Screen-space frames of Eave's toggle status item across ALL connected displays (AppKit global coordinates).
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

    /// Window IDs owned by Eave's own control items so the scanner excludes them.
    var ownedWindowIDs: Set<CGWindowID> {
        var ids = Set<CGWindowID>()
        let windows = [
            toggleItem.button?.window,
            hiddenSeparator.button?.window
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
        seedInitialPreferredPositionsIfNeeded()

        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        toggleItem.autosaveName = "eave.control.toggle"
        configureToggleButton()

        hiddenSeparator = NSStatusBar.system.statusItem(withLength: Self.collapsedSeparatorLength)
        hiddenSeparator.autosaveName = "eave.control.hidden"
        configureSeparatorButton(
            hiddenSeparator,
            image: Self.makeDividerImage(),
            tooltip: "Eave Hidden Divider (⌘-drag icons left to hide)"
        )

        applySeparatorLengths()
    }

    private func seedInitialPreferredPositionsIfNeeded() {
        let defaults = UserDefaults.standard
        let toggleKey = "NSStatusItem Preferred Position eave.control.toggle"
        let hiddenKey = "NSStatusItem Preferred Position eave.control.hidden"

        if defaults.object(forKey: toggleKey) == nil {
            defaults.set(0.0, forKey: toggleKey)
        }
        if defaults.object(forKey: hiddenKey) == nil {
            defaults.set(40.0, forKey: hiddenKey)
        }
    }

    /// Renders a crisp, ultra-compact centered dot (`•`) template divider glyph separating Visible and Hidden items.
    private static func makeDividerImage() -> NSImage {
        let size = NSSize(width: 8, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            let diameter: CGFloat = 4.0
            let dotRect = NSRect(
                x: (rect.width - diameter) / 2,
                y: (rect.height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            NSBezierPath(ovalIn: dotRect).fill()
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

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            toggleItem.button?.animator().alphaValue = isHiddenExpanded ? 1.0 : 0.85
        }
    }

    // MARK: - Actions & Context Menu

    @objc private func handleToggleClick(_ sender: NSStatusBarButton) {
        onWillHandleToggleInteraction?()

        guard let event = NSApp.currentEvent else {
            toggleHidden()
            return
        }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            presentContextMenu(from: sender)
            return
        }

        // The hover reveal usually fires a moment before the click lands. Treat that click as
        // "keep it open" instead of immediately collapsing what the user is about to use.
        if isHoverExpansion && !pointerLeftToggleSinceHoverReveal {
            promoteHoverExpansionToUser()
            return
        }

        toggleHidden()
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
                guard let self, self.isHiddenExpanded else { return }
                guard self.settings.rehideAutomatically
                    || self.isTransientForwardExpansion
                    || self.isHoverExpansion else { return }
                if self.isPointerProtectedFromRehide?() == true { return }
                // Clicking a revealed item frequently activates its owning app; that is not "switching away".
                if CFAbsoluteTimeGetCurrent() - self.lastMenuBarClickTime < Self.recentMenuBarClickSeconds { return }
                if Self.isPointInMenuBar(NSEvent.mouseLocation) { return }
                if self.isInteractionInProgress() {
                    self.scheduleAutoRehideIfNeeded()
                    return
                }
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

        let delay: TimeInterval
        if isTransientForwardExpansion {
            delay = Self.transientForwardRehideSeconds
        } else if isHoverExpansion {
            // Hover reveals are dismissed by pointer-leave; keep an inactivity fallback regardless of the setting.
            delay = EaveSettings.defaultAutoRehideDelaySeconds
        } else if settings.rehideAutomatically {
            delay = EaveSettings.defaultAutoRehideDelaySeconds
        } else {
            return
        }

        rehideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isHiddenExpanded else { return }
                if Self.isPointInMenuBar(NSEvent.mouseLocation)
                    || self.isPointerProtectedFromRehide?() == true
                    || self.isInteractionInProgress() {
                    self.scheduleAutoRehideIfNeeded()
                    return
                }
                self.collapseAll()
            }
        }
    }

    /// Menu-bar band test with a small cushion so pointer jitter at the bar's lower edge does not count as leaving.
    nonisolated static func isPointInMenuBar(_ point: CGPoint) -> Bool {
        for screen in NSScreen.screens where screen.frame.contains(point) {
            let visibleTopInset = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
            let barHeight = max(screen.safeAreaInsets.top, visibleTopInset, 24)
            return point.y >= screen.frame.maxY - barHeight - 4
        }
        return false
    }

    /// Detects an open NSMenu-style menu (any app) via WindowServer's pop-up menu window layer.
    nonisolated static func isAnyMenuOpenOnScreen() -> Bool {
        let popUpLayer = Int(CGWindowLevelForKey(.popUpMenuWindow))
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else {
            return false
        }
        return info.contains { window in
            (window[kCGWindowLayer as String] as? Int) == popUpLayer
        }
    }

    // MARK: - Control Item Order

    private static let togglePositionKey = "NSStatusItem Preferred Position eave.control.toggle"
    private static let hiddenPositionKey = "NSStatusItem Preferred Position eave.control.hidden"

    /// The divider must sit LEFT of the Eave icon. If a ⌘-drag put it on the right, a collapse would push
    /// the Eave icon (and every visible item between them) off-screen with no way to get it back.
    /// Works expanded or collapsed (collapsed, the 10,000pt divider's centre is far left of a correctly placed icon,
    /// and a ⌘-dragged-left icon ends up left of it). Re-seats the divider just left of the icon.
    /// Returns true when a repair was performed.
    @discardableResult
    func repairControlOrderIfNeeded() -> Bool {
        guard let toggleFrame = toggleItem.button?.window?.frame,
              let separatorFrame = hiddenSeparator.button?.window?.frame,
              toggleFrame.width > 0, separatorFrame.width > 0 else {
            return false
        }
        // Only comparable when both live on the same display's menu bar.
        guard abs(toggleFrame.midY - separatorFrame.midY) < 40 else { return false }
        guard Self.isControlOrderInvalid(toggleFrame: toggleFrame, separatorFrame: separatorFrame) else {
            return false
        }

        let defaults = UserDefaults.standard
        let togglePosition = defaults.double(forKey: Self.togglePositionKey)
        NSStatusBar.system.removeStatusItem(hiddenSeparator)
        defaults.set(togglePosition + toggleFrame.width + 2, forKey: Self.hiddenPositionKey)

        hiddenSeparator = NSStatusBar.system.statusItem(withLength: Self.expandedSeparatorLength)
        hiddenSeparator.autosaveName = "eave.control.hidden"
        configureSeparatorButton(
            hiddenSeparator,
            image: Self.makeDividerImage(),
            tooltip: "Eave Hidden Divider (⌘-drag icons left to hide)"
        )
        applySeparatorLengths()
        refreshToggleFramesCache()
        return true
    }

    /// Pure order check: the divider is invalid when its centre is at or right of the Eave icon's centre.
    nonisolated static func isControlOrderInvalid(toggleFrame: CGRect, separatorFrame: CGRect) -> Bool {
        separatorFrame.midX >= toggleFrame.midX
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
