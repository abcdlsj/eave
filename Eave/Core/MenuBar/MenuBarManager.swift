import AppKit
import Carbon.HIToolbox
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
    /// Grace period after a forwarded click before Eave starts checking whether the target's menu/popover closed.
    private static let transientForwardGraceSeconds: TimeInterval = 1.5
    /// Poll interval used while a forwarded menu/popover is still open.
    private static let transientForwardPollSeconds: TimeInterval = 0.5
    /// Hard ceiling so an app with a permanent floating window can't keep the bar expanded forever.
    private static let transientForwardMaxSeconds: CFTimeInterval = 120
    private var transientForwardStartTime: CFAbsoluteTime = 0
    /// A click this soon after a hover reveal is treated as "keep it open", not "collapse".
    private static let hoverClickPinWindowSeconds: CFTimeInterval = 0.9

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

    private(set) var isHiddenExpanded: Bool = false
    /// True when the menu bar was temporarily expanded solely to anchor a forwarded menu-bar-only app click.
    private(set) var isTransientForwardExpansion: Bool = false
    private(set) var isContextMenuOpen: Bool = false
    /// pid of the app whose menu/popover was opened by a transient forwarded click.
    private(set) var transientForwardTargetPID: pid_t?
    /// True when the current expansion came from hovering the Eave icon (not an explicit click/hotkey).
    private(set) var isHoverExpansion: Bool = false
    private var hoverExpansionTime: CFAbsoluteTime = 0

    /// Callbacks wired by AppCoordinator for cross-module orchestration.
    var onRequestOpenSearch: (() -> Void)?
    var onRequestOpenSettings: (() -> Void)?
    var onRequestOpenOnboarding: (() -> Void)?
    var onExpansionChanged: ((Bool) -> Void)?
    var onToggleHoverChanged: ((Bool) -> Void)?
    var onWillHandleToggleInteraction: (() -> Void)?
    /// Lets the coordinator consume a left click (e.g. to pin a visible Second Row) before it toggles.
    var shouldInterceptToggleClick: (() -> Bool)?
    var isPointerProtectedFromRehide: (() -> Bool)?
    /// Returns true while auto-rehide must be paused entirely (e.g. onboarding teaching ⌘-drag).
    var isAutoRehidePaused: (() -> Bool)?

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
        isTransientForwardExpansion = false
        transientForwardTargetPID = nil
        isHoverExpansion = false
        isHiddenExpanded = true
        applySeparatorLengths()
        scheduleAutoRehideIfNeeded()
        onExpansionChanged?(true)
    }

    /// Inline reveal triggered by hovering the Eave icon. A click that lands right after it pins the
    /// expansion instead of collapsing it (see `handleToggleClick`).
    func expandHiddenFromHover() {
        expandHidden()
        isHoverExpansion = true
        hoverExpansionTime = CFAbsoluteTimeGetCurrent()
    }

    /// Briefly reveals the hidden section so a menu-bar-only popover/menu can anchor at the top-right,
    /// then collapses once the target app's menu/popover is dismissed.
    func expandTemporarilyForForwarding(targetPID: pid_t) {
        isTransientForwardExpansion = true
        transientForwardTargetPID = targetPID
        transientForwardStartTime = CFAbsoluteTimeGetCurrent()
        isHoverExpansion = false
        isHiddenExpanded = true
        applySeparatorLengths()
        scheduleAutoRehideIfNeeded()
        onExpansionChanged?(true)
    }

    /// True while the transient forwarding target still shows a menu, popover, or panel on screen.
    func transientTargetHasOpenUI() -> Bool {
        guard isTransientForwardExpansion, let pid = transientForwardTargetPID else { return false }
        guard CFAbsoluteTimeGetCurrent() - transientForwardStartTime < Self.transientForwardMaxSeconds else { return false }
        return Self.hasOpenTransientUI(pid: pid)
    }

    /// Detects on-screen menus/popovers owned by `pid` using only window metadata (layer, bounds, owner),
    /// which never requires Screen Recording permission.
    nonisolated static func hasOpenTransientUI(pid: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else {
            return false
        }
        return list.contains { entry in
            guard (entry[kCGWindowOwnerPID as String] as? Int).map({ pid_t($0) }) == pid else { return false }
            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            return isTransientUIWindow(layer: layer, bounds: windowBounds(entry))
        }
    }

    /// Pure classifier: menus (layer 101), popovers and floating panels count; status item windows (layer 25)
    /// and the app's normal document windows (layer 0) do not.
    nonisolated static func isTransientUIWindow(layer: Int, bounds: CGRect) -> Bool {
        guard layer != Int(CGWindowLevelForKey(.statusWindow)) else { return false }
        guard layer > 0 else { return false }
        return bounds.width > 4 && bounds.height > 4
    }

    private nonisolated static func windowBounds(_ entry: [String: Any]) -> CGRect {
        guard let dict = entry[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: dict as CFDictionary) else {
            return .zero
        }
        return rect
    }

    func collapseIfTransient() {
        guard isTransientForwardExpansion else { return }
        collapseAll()
    }

    func collapseAll() {
        guard isHiddenExpanded else { return }
        rehideTimer?.invalidate()
        rehideTimer = nil
        guard isSeparatorOrderValid else {
            // The divider was ⌘-dragged to the right of the Eave icon. Collapsing now would push the
            // Eave icon itself off-screen, so stay expanded and let the user drag the divider back.
            isTransientForwardExpansion = false
            transientForwardTargetPID = nil
            isHoverExpansion = false
            NSSound.beep()
            return
        }
        isHiddenExpanded = false
        isTransientForwardExpansion = false
        transientForwardTargetPID = nil
        isHoverExpansion = false
        applySeparatorLengths()
        onExpansionChanged?(false)
    }

    /// The hidden divider must sit to the LEFT of the Eave icon; otherwise inflating it hides Eave too.
    var isSeparatorOrderValid: Bool {
        guard let separatorFrame = hiddenSeparator.button?.window?.frame,
              let toggleFrame = toggleItem.button?.window?.frame else {
            return true
        }
        return Self.isSeparatorOrderValid(separatorFrame: separatorFrame, toggleFrame: toggleFrame)
    }

    nonisolated static func isSeparatorOrderValid(separatorFrame: CGRect, toggleFrame: CGRect) -> Bool {
        guard separatorFrame.width > 0, toggleFrame.width > 0 else { return true }
        // Only comparable when both live on the same menu bar row.
        guard abs(separatorFrame.midY - toggleFrame.midY) < 20 else { return true }
        return separatorFrame.midX < toggleFrame.midX
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
            let isControlCenter = MenuBarItemScanner.isControlCenterOwnerName(win.ownerName)
            let lowerName = win.windowName.lowercased()
            let isToggle = (isControlCenter && (lowerName == "eave.control.toggle" || lowerName == lowerOwn))
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
            tooltip: "Eave divider: ⌘-drag icons to its left to hide them. Keep it left of the Eave icon."
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
        // performClick in presentContextMenu must open the attached menu; never re-enter.
        guard !isContextMenuOpen else { return }
        onWillHandleToggleInteraction?()

        guard let event = NSApp.currentEvent else {
            toggleHidden()
            return
        }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            presentContextMenu(from: sender)
            return
        }

        if shouldInterceptToggleClick?() == true {
            return
        }

        // A click arriving right after a hover reveal means "I want these open", so keep them
        // open (and turn the hover reveal into a regular expansion) rather than collapsing.
        if isHiddenExpanded, isHoverExpansion,
           CFAbsoluteTimeGetCurrent() - hoverExpansionTime < Self.hoverClickPinWindowSeconds {
            isHoverExpansion = false
            scheduleAutoRehideIfNeeded()
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

        let toggleTitle = isHiddenExpanded ? "Hide Hidden Items" : "Show Hidden Items"
        let toggleSymbol = isHiddenExpanded ? "eye.slash" : "eye"
        let toggleMenuItem = makeItem(title: toggleTitle, symbol: toggleSymbol, action: #selector(menuToggleHidden))
        Self.applyShortcutHint(settings.hotKey(for: .toggleHidden), to: toggleMenuItem)
        menu.addItem(toggleMenuItem)
        let searchItem = makeItem(title: "Search Menu Bar…", symbol: "magnifyingglass", action: #selector(menuOpenSearch))
        Self.applyShortcutHint(settings.hotKey(for: .openSearch), to: searchItem)
        menu.addItem(searchItem)

        menu.addItem(.separator())

        menu.addItem(makeItem(title: "Quick Start Guide…", symbol: "sparkles", action: #selector(menuOpenOnboarding)))
        menu.addItem(makeItem(title: "Settings…", symbol: "gearshape", action: #selector(menuOpenSettings), keyEquivalent: ","))

        menu.addItem(.separator())

        menu.addItem(makeItem(title: "Quit Eave", symbol: "power", action: #selector(menuQuit), keyEquivalent: "q"))

        isContextMenuOpen = true
        defer { isContextMenuOpen = false }
        toggleItem.menu = menu
        button.performClick(nil)
        // Clear menu immediately so subsequent left clicks continue invoking handleToggleClick.
        toggleItem.menu = nil
    }

    /// Shows the global hotkey next to a context menu item (display only; letters only).
    private static func applyShortcutHint(_ combo: KeyCombo?, to item: NSMenuItem) {
        guard let combo else { return }
        let label = KeyCombo.keyLabel(for: combo.keyCode)
        guard label.count == 1, label.first?.isLetter == true else { return }
        item.keyEquivalent = label.lowercased()
        var mask: NSEvent.ModifierFlags = []
        if combo.carbonModifiers & UInt32(cmdKey) != 0 { mask.insert(.command) }
        if combo.carbonModifiers & UInt32(optionKey) != 0 { mask.insert(.option) }
        if combo.carbonModifiers & UInt32(controlKey) != 0 { mask.insert(.control) }
        if combo.carbonModifiers & UInt32(shiftKey) != 0 { mask.insert(.shift) }
        item.keyEquivalentModifierMask = mask
    }

    @objc private func menuToggleHidden() { toggleHidden() }
    @objc private func menuOpenSearch() { onRequestOpenSearch?() }
    @objc private func menuOpenOnboarding() { onRequestOpenOnboarding?() }
    @objc private func menuOpenSettings() { onRequestOpenSettings?() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: - Auto-Rehide

    private func observeWorkspace() {
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let activatedPID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            Task { @MainActor [weak self] in
                guard let self, self.isHiddenExpanded else { return }
                guard self.settings.rehideAutomatically || self.isTransientForwardExpansion else { return }
                if self.isAutoRehidePaused?() == true { return }
                if self.isPointerProtectedFromRehide?() == true { return }
                // The forwarded app activating itself to show its popover is expected, not an app switch.
                if self.isTransientForwardExpansion,
                   let target = self.transientForwardTargetPID,
                   activatedPID == target {
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
            delay = Self.transientForwardGraceSeconds
        } else if settings.rehideAutomatically {
            delay = EaveSettings.defaultAutoRehideDelaySeconds
        } else {
            return
        }

        rehideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isHiddenExpanded else { return }
                if self.isTransientForwardExpansion {
                    // Keep the status item anchored while the forwarded menu/popover is still open;
                    // collapse shortly after it is dismissed.
                    if self.transientTargetHasOpenUI() || self.isCursorInMenuBar() {
                        self.scheduleTransientPoll()
                        return
                    }
                    self.collapseAll()
                    return
                }
                if self.isAutoRehidePaused?() == true
                    || self.isCursorInMenuBar()
                    || self.isPointerProtectedFromRehide?() == true {
                    self.scheduleAutoRehideIfNeeded()
                    return
                }
                self.collapseAll()
            }
        }
    }

    private func scheduleTransientPoll() {
        rehideTimer?.invalidate()
        rehideTimer = Timer.scheduledTimer(withTimeInterval: Self.transientForwardPollSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isHiddenExpanded, self.isTransientForwardExpansion else { return }
                if self.transientTargetHasOpenUI() || self.isCursorInMenuBar() {
                    self.scheduleTransientPoll()
                } else {
                    self.collapseAll()
                }
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
