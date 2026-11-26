# Eave Design

**Eave** is a native macOS menu bar manager with textless Notch signals, built in pure Swift (`AppKit` + `SwiftUI`) with zero third-party dependencies. It targets **macOS 15.0+** and adopts **macOS 26 (Tahoe)** Liquid Glass.

## Design Principles

1. **Restraint First**: The Notch stays single-line and hardware-height — no downward text drawers or desktop widgets. It surfaces only quiet visual signals (icon + accent dot, optional 3-bar activity wave, or numeric count) with one-click deep links.
2. **Progressive Privacy (Zero Screen Recording)**: Core two-section hiding works with zero permissions. A single **Accessibility** grant unlocks hidden-app discovery, Dock badge alerts, and menu-bar click forwarding. Native app icons are used everywhere; Screen Recording is never requested.
3. **Zero Private APIs**: All hiding, scanning, and click forwarding rely strictly on public AppKit, CoreGraphics, Accessibility, and Carbon HotKey APIs.
4. **Local-Only & Zero Leakage**: No telemetry; notification payloads, badges, and window contents are never logged.

## Architecture

Strictly directional dependencies: `App` -> `UI` / `Core` -> `Models`.

- **`Models`**: `EaveSettings` (UserDefaults-backed `@Observable`), `MenuBarModels`, `NotchModels` (`NotchState`, `NotchAlert`, `AmbientIndicator`, `BridgePayload`).
- **`Core/MenuBar`**:
  - `MenuBarManager` — Two-section `NSStatusItem` layout (`toggle` + `hiddenSeparator`) and unified auto-rehide (8s idle or app switch).
  - `MenuBarItemScanner` — Dual-track discovery (`AXExtrasMenuBar` + `CGWindowList` layer-25 including macOS 26 Control Center proxy windows).
  - `MenuBarClickForwarder` — Smart routing by `NSApplication.ActivationPolicy` and mouse button.
  - `MenuBarEventMonitor` — Low-overhead multi-display hover detection and outside-click dismissal.
  - `MenuBarSpacingManager` — `NSGlobalDomain` `NSStatusItemSpacing` / `NSStatusItemSelectionPadding`.
- **`Core/Notch` & `Core/Signals`**:
  - `NotchGeometryResolver`, `NotchStateMachine` (`idle` / `ambient` / `peek`), `NotchPanelController` (non-activating pass-through `NSPanel`).
  - `SignalHub` aggregating `DockBadgeMonitor`, `MenuBarAXWatcher`, and `NotchBridge`.
- **`UI`**: `SecondRowBarController` / `SecondRowBarView`, `NotchContainerView` / `NotchPeekView` / `NotchShape`, `MenuBarSearchPanel`, `SettingsView`, `EaveDesignSystem`, `AppIconService`.

## Core Mechanisms

### 1. Menu Bar Hiding & Second Row
- **Two-Section Engine**: A compact dot separator (`eave.control.hidden`) inflates to `10,000pt` when collapsed to push items left of it off-screen, and shrinks to `10pt` when expanded so users can `⌘`-drag items cleanly.
- **Hover vs. Click Separation**:
  - **Left-click Eave** expands/collapses hidden items inline.
  - **Hover Eave** (across any connected display) reveals hidden items inline or in the floating **Second-Row Bar** (horizontal scroll or multi-row wrap, 120fps Dock magnification).
- **Smart Click Routing**:
  - Regular windowed apps (`activationPolicy == .regular`) on left-click invoke `NSWorkspace.openApplication` directly — bringing/reopening the main window with **zero menu bar expansion**.
  - Menu-bar-only utilities (`activationPolicy == .accessory`, e.g., Tailscale, Clash) and right-clicks transiently expand the hidden section so native menus/popovers anchor cleanly at the top-right, dispatch `AXPress` / `AXShowMenu` (or synthetic left/right `CGEvent` click), and collapse shortly after the target menu or popover closes (window-layer check, 120s ceiling).

### 2. Textless Notch State Machine
- **Three States**: `.idle` (pass-through, invisible) ↔ `.ambient([AmbientIndicator])` (persistent wings) ↔ `.peek(NotchAlert)` (transient wings with one-shot arrival rim shimmer + sonar ping).
- **Single-Line Visual Grammar**:
  - **Left wing**: Icon resolved in strict priority: local file `icon` > SF Symbol `symbol` > installed app `bundleID` > fallback symbol.
  - **Right wing**: Custom `accent` (`#RRGGBB`) breathing dot by default, optional 3-bar activity wave (`style=wave`), or strictly numeric `badge` (e.g., `3`, `99+`; arbitrary text is stripped).
  - **Interaction**: Hover pauses peek dismissal; click opens `targetURL` or activates `bundleIdentifier`.

### 3. NotchBridge Protocol
- Transports: URL Scheme (`eave://notify?...`, `eave://clear?id=...`) and `DistributedNotificationCenter` (`com.abcdlsj.eave.notch.notify`).
- Accepted keys: `id`, `mode` (`peek` | `ambient` | `clear`), `icon`, `symbol`, `bundleID`, `accent`, `badge` (numeric only), `style` (`dot` | `wave`), `loop` (`true` | `false`, default `false`), `url`, `duration` (`1`–`300s`; defaults to user Peek duration for `peek`, optional auto-expiry TTL for `ambient`).
- Sending a `peek` with the same `id` as an active `ambient` signal automatically clears that `ambient` entry, enabling clean `running -> done` transitions.

### 4. Search, Appearance & Verification
- **Quick Search (`⌥⌘K`)**: Fuzzy-ranks all visible and hidden items with subsequence highlighting and smart click routing.
- **Appearance Sync**: `System` / `Light` / `Dark` updates both `NSWindow.appearance` and SwiftUI `.preferredColorScheme` live across Settings, Second Row, and Search.
- **Boundaries & Tests**: Non-sandboxed (`com.apple.security.app-sandbox = false`) for Accessibility and global defaults. Pure logic (geometry, state machine, badge diff, bridge parsing, click routing, layout metrics, search ranking, settings persistence) is verified via `xcodebuild test`.
