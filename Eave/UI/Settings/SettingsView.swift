import AppKit
import SwiftUI

/// Restrained, monochrome editorial Settings studio for Eave (Linear / Alcove / Apple Studio aesthetic).
struct SettingsView: View {
    let coordinator: AppCoordinator

    @State private var selectedTab: SettingsTab = .general
    @State private var hoveredTab: SettingsTab?
    @State private var isStatusHovered = false
    @Namespace private var sidebarNamespace

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case notch = "Notch"
        case shortcuts = "Shortcuts"
        case permissions = "Permissions"
        case bridge = "Bridge"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .general: "slider.horizontal.3"
            case .notch: "macbook"
            case .shortcuts: "command"
            case .permissions: "lock.shield"
            case .bridge: "bolt.horizontal"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 200)
                .background(.ultraThinMaterial)

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 0.65)

            ScrollView {
                detailPane
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(selectedTab)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 740, height: 540)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Minimalist brand header
            HStack(spacing: 10) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Eave")
                        .font(.system(size: 14.5, weight: .semibold))
                        .tracking(-0.2)
                    Text("Version 0.1.0")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 36)
            .padding(.bottom, 18)

            VStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    sidebarRow(tab)
                }
            }

            Spacer()

            // Quiet status footer (clickable -> Permissions)
            Button {
                EaveHaptics.tick()
                withAnimation(EaveMotion.tabSwitch) {
                    selectedTab = .permissions
                }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(
                            coordinator.permissions.hasAccessibility
                                ? Color(red: 0.20, green: 0.72, blue: 0.42)
                                : Color(red: 0.90, green: 0.56, blue: 0.18)
                        )
                        .frame(width: 6, height: 6)

                    Text(coordinator.permissions.hasAccessibility ? "Full Access" : "Basic Mode")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if !coordinator.permissions.hasAccessibility {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(isStatusHovered ? 0.065 : 0.03))
                )
                .padding(.horizontal, 11)
                .padding(.bottom, 14)
            }
            .buttonStyle(EaveTactileButtonStyle(pressedScale: 0.98))
            .onHover { hovering in
                withAnimation(EaveMotion.hover) {
                    isStatusHovered = hovering
                }
            }
        }
    }

    private func sidebarRow(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        let isHovered = hoveredTab == tab
        let needsAttention = tab == .permissions && !coordinator.permissions.hasAccessibility

        return Button {
            if selectedTab != tab {
                EaveHaptics.tick()
                withAnimation(EaveMotion.tabSwitch) {
                    selectedTab = tab
                }
            }
        } label: {
            HStack(spacing: 9.5) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 18, alignment: .center)

                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()

                if needsAttention {
                    Circle()
                        .fill(Color(red: 0.90, green: 0.56, blue: 0.18))
                        .frame(width: 5.5, height: 5.5)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7.5)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .matchedGeometryEffect(id: "activeSidebarRow", in: sidebarNamespace)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                }
            }
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(EaveTactileButtonStyle(pressedScale: 0.98))
        .onHover { hovering in
            withAnimation(EaveMotion.hover) {
                hoveredTab = hovering ? tab : (hoveredTab == tab ? nil : hoveredTab)
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        switch selectedTab {
        case .general:
            GeneralSettingsTab(coordinator: coordinator)
        case .notch:
            NotchSettingsTab(coordinator: coordinator)
        case .shortcuts:
            ShortcutsSettingsTab(coordinator: coordinator)
        case .permissions:
            PermissionsSettingsTab(coordinator: coordinator)
        case .bridge:
            BridgeSettingsTab(coordinator: coordinator)
        }
    }
}

// MARK: - General Tab

private struct GeneralSettingsTab: View {
    let coordinator: AppCoordinator
    @Bindable var settings: EaveSettings
    @State private var spacingValue: Double = 10
    @State private var paddingValue: Double = 8
    @State private var appliedFeedback = false

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self._settings = Bindable(coordinator.settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            EavePageHeader(
                title: "General",
                subtitle: "Menu bar sections, auto-rehide behavior, and global icon spacing."
            )

            EaveSettingsCard("Startup & Appearance") {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Appearance")
                            .font(.system(size: 13))
                        Text("Follow macOS Day/Night automatically, or lock to Light / Dark.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 10)

                    Picker("", selection: $settings.appearanceMode) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 196)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10.5)
                .onChange(of: settings.appearanceMode) { _, _ in
                    EaveHaptics.tick()
                    coordinator.applyAppearance()
                }
                EaveCardDivider()
                EaveSettingsToggleRow(
                    "Launch Eave at login",
                    subtitle: "Start quietly in the menu bar when you sign in.",
                    isOn: Binding(
                        get: { coordinator.launchAtLogin.isEnabled },
                        set: { coordinator.launchAtLogin.setEnabled($0) }
                    )
                )
                EaveCardDivider()
                EaveSettingsToggleRow(
                    "Enable Always-Hidden section",
                    subtitle: "Secondary divider for rarely accessed items. Reveal with ⌥ + Click.",
                    isOn: $settings.enableAlwaysHiddenSection
                )
                .onChange(of: settings.enableAlwaysHiddenSection) { _, _ in
                    coordinator.menuBarManager.syncConfiguration()
                }
                EaveCardDivider()
                EaveSettingsToggleRow(
                    "Open Notch Bar on primary click",
                    subtitle: "Open the obsidian Notch Bar instead of expanding inline.",
                    isOn: $settings.useNotchBarOnToggle
                )
            }

            EaveSettingsCard("Hover Reveal") {
                EaveSettingsToggleRow(
                    "Hover Eave icon to show hidden items",
                    subtitle: "Reveal tucked items automatically when your pointer rests on the Eave icon.",
                    isOn: $settings.expandOnEaveHover.animation(EaveMotion.microSpring)
                )
                .onChange(of: settings.expandOnEaveHover) { _, _ in
                    coordinator.syncHoverSettings()
                }

                if settings.expandOnEaveHover {
                    EaveCardDivider()

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Display style")
                                .font(.system(size: 13))
                            Text(
                                settings.hoverDisplayMode == .secondRow
                                    ? "Show hidden items in a floating second row beneath the menu bar."
                                    : "Expand hidden items inline inside the macOS menu bar."
                            )
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 10)

                        Picker("", selection: $settings.hoverDisplayMode.animation(EaveMotion.microSpring)) {
                            ForEach(HoverDisplayMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10.5)
                    .onChange(of: settings.hoverDisplayMode) { _, _ in
                        coordinator.syncHoverSettings()
                    }

                    EaveCardDivider()

                    HStack(spacing: 12) {
                        Text("Hover delay")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.hoverDelaySeconds, in: 0.10...0.60, step: 0.05)
                        Text(String(format: "%.2fs", settings.hoverDelaySeconds))
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    if settings.hoverDisplayMode == .secondRow {
                        EaveCardDivider()

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Overflow layout")
                                    .font(.system(size: 13))
                                Text(
                                    settings.secondRowLayoutMode == .horizontalScroll
                                        ? "Keep a single sleek row and swipe horizontally through extra items."
                                        : "Wrap extra items into additional rows automatically."
                                )
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 10)

                            Picker("", selection: $settings.secondRowLayoutMode) {
                                ForEach(SecondRowLayoutMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 210)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10.5)
                        .onChange(of: settings.secondRowLayoutMode) { _, _ in
                            coordinator.syncHoverSettings()
                        }

                        EaveCardDivider()

                        VStack(alignment: .leading, spacing: 11) {
                            HStack(spacing: 12) {
                                Text("Items per row")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.secondary)
                                Slider(
                                    value: Binding(
                                        get: { Double(settings.secondRowItemsPerRow) },
                                        set: { settings.secondRowItemsPerRow = Int($0.rounded()) }
                                    ),
                                    in: Double(EaveSettings.secondRowItemsPerRowRange.lowerBound)...Double(EaveSettings.secondRowItemsPerRowRange.upperBound),
                                    step: 1
                                )
                                Text("\(settings.secondRowItemsPerRow)")
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .trailing)
                            }

                            secondRowLayoutPreview

                            HStack(spacing: 8) {
                                Button("Preview Second Row") {
                                    EaveHaptics.tick()
                                    coordinator.showSecondRowBar(pinnedForPreview: true)
                                }
                                .buttonStyle(EaveSecondaryButtonStyle())

                                Spacer()
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .transition(.opacity)
                        .onChange(of: settings.secondRowItemsPerRow) { _, _ in
                            coordinator.syncHoverSettings()
                        }
                    }
                }
            }

            EaveSettingsCard("Auto-Rehide & Gestures") {
                EaveSettingsToggleRow(
                    "Automatically rehide expanded items",
                    subtitle: "Pauses automatically while the pointer stays in the menu bar or Notch.",
                    isOn: $settings.rehideAutomatically.animation(EaveMotion.microSpring)
                )

                if settings.rehideAutomatically {
                    EaveCardDivider()
                    HStack(spacing: 12) {
                        Text("Rehide delay")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.rehideDelaySeconds, in: 3...20, step: 1)
                        Text("\(Int(settings.rehideDelaySeconds))s")
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .transition(.opacity)
                }

                EaveCardDivider()
                EaveSettingsToggleRow("Rehide when switching applications", isOn: $settings.rehideOnAppSwitch)
                EaveCardDivider()
                EaveSettingsToggleRow("Scroll on menu bar to expand / collapse", isOn: $settings.expandOnMenuBarScroll)
            }

            EaveSettingsCard(
                "Menu Bar Spacing",
                subtitle: "Adjusts global NSStatusItemSpacing. Apps adopt new metrics on relaunch."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    menuBarSpacingPreview

                    HStack(spacing: 12) {
                        Text("Icon spacing")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .frame(width: 110, alignment: .leading)
                        Slider(value: $spacingValue, in: 4...20, step: 1)
                        Text("\(Int(spacingValue)) pt")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }

                    HStack(spacing: 12) {
                        Text("Selection padding")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .frame(width: 110, alignment: .leading)
                        Slider(value: $paddingValue, in: 2...16, step: 1)
                        Text("\(Int(paddingValue)) pt")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }

                    HStack(spacing: 8) {
                        Button {
                            coordinator.spacingManager.apply(
                                spacing: Int(spacingValue),
                                selectionPadding: Int(paddingValue)
                            )
                            EaveHaptics.tap()
                            withAnimation(EaveMotion.microSpring) {
                                appliedFeedback = true
                            }
                            Task {
                                try? await Task.sleep(nanoseconds: 1_800_000_000)
                                withAnimation(EaveMotion.hover) {
                                    appliedFeedback = false
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                if appliedFeedback {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10.5, weight: .bold))
                                }
                                Text(appliedFeedback ? "Applied" : "Apply Spacing")
                            }
                        }
                        .buttonStyle(EaveProminentButtonStyle(isConfirmed: appliedFeedback))

                        Button("Reset Default") {
                            coordinator.spacingManager.resetToSystemDefault()
                            withAnimation(EaveMotion.microSpring) {
                                spacingValue = 10
                                paddingValue = 8
                            }
                        }
                        .buttonStyle(EaveSecondaryButtonStyle())

                        Spacer()
                    }
                    .padding(.top, 2)
                }
                .padding(14)
            }
        }
        .onAppear {
            coordinator.spacingManager.reload()
            if let s = coordinator.spacingManager.config.spacing { spacingValue = Double(s) }
            if let p = coordinator.spacingManager.config.selectionPadding { paddingValue = Double(p) }
        }
    }

    private var secondRowLayoutPreview: some View {
        let sampleSymbols = [
            "bubble.left", "cloud", "network", "lock.shield", "terminal",
            "music.note", "tray", "calendar", "bolt", "paperplane",
            "waveform", "globe", "gearshape", "sparkles", "cpu", "antenna.radiowaves.left.and.right"
        ]
        let sampleCount = max(settings.secondRowItemsPerRow + 4, 12)
        let previewItems = Array(sampleSymbols.prefix(min(sampleCount, sampleSymbols.count)))
        let visibleViewportWidth = CGFloat(settings.secondRowItemsPerRow) * 22
            + CGFloat(max(settings.secondRowItemsPerRow - 1, 0)) * 4

        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Second Row Preview")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(
                    settings.secondRowLayoutMode == .horizontalScroll
                        ? "\(settings.secondRowItemsPerRow) visible · swipe ↔"
                        : "\(settings.secondRowItemsPerRow) / row"
                )
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            }

            if settings.secondRowLayoutMode == .horizontalScroll {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(previewItems.enumerated()), id: \.offset) { _, symbol in
                            previewCell(symbol)
                        }
                    }
                }
                .frame(maxWidth: visibleViewportWidth, alignment: .leading)
            } else {
                let rows = SecondRowLayoutMetrics.chunkedRows(previewItems, itemsPerRow: settings.secondRowItemsPerRow)
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 4) {
                                ForEach(Array(row.enumerated()), id: \.offset) { _, symbol in
                                    previewCell(symbol)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.065), lineWidth: 0.6)
                )
        )
    }

    private func previewCell(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.primary.opacity(0.72))
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.065))
            )
    }

    private var menuBarSpacingPreview: some View {
        let previewSymbols = ["bubble.left", "cloud", "network", "wifi", "battery.100percent"]
        return HStack {
            Text("Menu Bar")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.tertiary)

            Spacer()

            HStack(spacing: max(2, spacingValue * 0.65)) {
                ForEach(Array(previewSymbols.enumerated()), id: \.offset) { index, sym in
                    Image(systemName: sym)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary.opacity(index == 2 ? 0.95 : 0.65))
                        .padding(.horizontal, max(2, paddingValue * 0.5))
                        .padding(.vertical, 3.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                .fill(index == 2 ? Color.primary.opacity(0.09) : Color.clear)
                        )
                }
            }
            .animation(EaveMotion.microSpring, value: spacingValue)
            .animation(EaveMotion.microSpring, value: paddingValue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.065), lineWidth: 0.6)
                )
        )
    }
}

// MARK: - Notch Tab

private struct NotchSettingsTab: View {
    let coordinator: AppCoordinator
    @Bindable var settings: EaveSettings
    @State private var newBundleID: String = ""

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self._settings = Bindable(coordinator.settings)
    }

    private var runningRegularApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            EavePageHeader(
                title: "Notch",
                subtitle: "Pure-obsidian notifications and subtle status beacons fused to your hardware notch."
            )

            // Studio-minimal interactive Notch preview & test controls
            notchPreviewStage

            EaveSettingsCard("Presentation") {
                EaveSettingsToggleRow(
                    "Peek hidden app notifications",
                    subtitle: "Silently unfurls app icon and unread count flanking the camera.",
                    isOn: $settings.enableNotchPeek.animation(EaveMotion.microSpring)
                )
                EaveCardDivider()
                EaveSettingsToggleRow(
                    "Ambient status wings",
                    subtitle: "Minimalist dot and count resting on the notch edge while unread items persist.",
                    isOn: $settings.enableAmbientIndicators.animation(EaveMotion.microSpring)
                )
                .onChange(of: settings.enableAmbientIndicators) { _, _ in
                    coordinator.signalHub.syncSettings()
                }
                EaveCardDivider()
                EaveSettingsToggleRow(
                    "Watch menu-bar-only app status changes",
                    subtitle: "Detects state transitions for background VPN, proxy, and utility apps via Accessibility.",
                    isOn: $settings.enableMenuBarAXWatcher
                )
                .onChange(of: settings.enableMenuBarAXWatcher) { _, _ in
                    coordinator.signalHub.syncSettings()
                }
                EaveCardDivider()
                EaveSettingsToggleRow(
                    "Use raw live pixel capture",
                    subtitle: "Off by default to display crisp native App Icons with zero screen capture.",
                    isOn: $settings.enableLiveIconCapture
                )
                EaveCardDivider()
                HStack(spacing: 12) {
                    Text("Peek duration")
                        .font(.system(size: 13))
                    Slider(value: $settings.peekDurationSeconds, in: 2...10, step: 0.5)
                    Text(String(format: "%.1fs", settings.peekDurationSeconds))
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10.5)
            }

            EaveSettingsCard("Watched Applications") {
                EaveSettingsToggleRow(
                    "Automatically watch hidden apps",
                    subtitle: "Tracking \(coordinator.signalHub.discoveredHiddenBundleIDs.count) auto-discovered · \(settings.watchedBundleIDs.count) pinned.",
                    isOn: $settings.watchHiddenAppsAutomatically
                )

                EaveCardDivider()

                HStack(spacing: 8) {
                    Menu {
                        ForEach(runningRegularApps, id: \.processIdentifier) { app in
                            if let id = app.bundleIdentifier {
                                Button(app.localizedName ?? id) {
                                    withAnimation(EaveMotion.microSpring) {
                                        settings.addWatchedBundleID(id)
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Add Running App", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .menuStyle(.borderedButton)
                    .fixedSize()

                    TextField("or bundle identifier...", text: $newBundleID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                    Button("Add") {
                        withAnimation(EaveMotion.microSpring) {
                            settings.addWatchedBundleID(newBundleID)
                            newBundleID = ""
                        }
                    }
                    .buttonStyle(EaveSecondaryButtonStyle())
                    .disabled(newBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(14)

                if !settings.watchedBundleIDs.isEmpty {
                    ForEach(settings.watchedBundleIDs, id: \.self) { bundleID in
                        EaveCardDivider()
                        WatchedAppRow(bundleID: bundleID) {
                            withAnimation(EaveMotion.microSpring) {
                                settings.removeWatchedBundleID(bundleID)
                            }
                        }
                    }
                }
            }
        }
    }

    private var notchPreviewStage: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
                    .frame(height: 68)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.65)
                    )

                // Precision miniature hardware notch
                HStack(spacing: 0) {
                    if settings.enableNotchPeek || settings.enableAmbientIndicators {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 28)
                            .transition(.opacity)
                    }

                    Circle()
                        .fill(Color(white: 0.13))
                        .overlay(Circle().strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
                        .frame(width: 5.5, height: 5.5)
                        .frame(width: 82)

                    if settings.enableNotchPeek || settings.enableAmbientIndicators {
                        Text("3")
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.90))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                            .frame(width: 28)
                            .transition(.opacity)
                    }
                }
                .frame(height: 24)
                .padding(.horizontal, 8)
                .background(
                    NotchShape(topCornerRadius: 6.5, bottomCornerRadius: 9.5)
                        .fill(Color.black)
                        .overlay(
                            NotchBottomRimShape(topCornerRadius: 6.5, bottomCornerRadius: 9.5)
                                .stroke(.white.opacity(0.10), lineWidth: 0.5)
                        )
                )
                .animation(EaveMotion.notchMorph, value: settings.enableNotchPeek)
                .animation(EaveMotion.notchMorph, value: settings.enableAmbientIndicators)
            }

            HStack(spacing: 8) {
                Button("Preview Notch Peek") {
                    coordinator.signalHub.sendTestPeek()
                }
                .buttonStyle(EaveProminentButtonStyle())

                Button("Toggle Notch Bar") {
                    coordinator.toggleNotchBar()
                }
                .buttonStyle(EaveSecondaryButtonStyle())

                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.65)
        )
    }
}

private struct WatchedAppRow: View {
    let bundleID: String
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        let resolved = AppIconService.shared.resolve(
            bundleIdentifier: bundleID,
            fallbackSymbol: "app.fill",
            fallbackAccentHex: nil
        )
        let appName = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { $0.deletingPathExtension().lastPathComponent } ?? bundleID

        HStack(spacing: 11) {
            if let img = resolved.image {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "app")
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(appName)
                    .font(.system(size: 12.5, weight: .medium))
                Text(bundleID)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button(role: .destructive) {
                EaveHaptics.tick()
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(isHovered ? .primary : .tertiary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(isHovered ? 0.08 : 0.0)))
            }
            .buttonStyle(EaveTactileButtonStyle(pressedScale: 0.88))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8.5)
        .onHover { hovering in
            withAnimation(EaveMotion.hover) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Shortcuts Tab

private struct ShortcutsSettingsTab: View {
    let coordinator: AppCoordinator
    @State private var restoredFeedback = false

    private func subtitle(for action: HotKeyAction) -> String {
        switch action {
        case .toggleHidden: "Expand or collapse hidden menu bar items inline."
        case .toggleNotchBar: "Drop down Eave's Notch Bar from any workspace."
        case .openSearch: "Open the keyboard-first menu bar search palette."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            EavePageHeader(
                title: "Shortcuts",
                subtitle: "Global keybindings for instant, pointer-free control."
            )

            EaveSettingsCard("Global Shortcuts") {
                ForEach(Array(HotKeyAction.allCases.enumerated()), id: \.element.id) { index, action in
                    if index > 0 {
                        EaveCardDivider()
                    }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                                .font(.system(size: 13))
                            Text(subtitle(for: action))
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HotKeyRecorderView(combo: coordinator.settings.hotKey(for: action)) { newCombo in
                            coordinator.settings.setHotKey(newCombo, for: action)
                            coordinator.hotKeyManager.register(action: action, combo: newCombo)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                }
            }

            HStack {
                Button {
                    coordinator.settings.resetHotKeys()
                    coordinator.hotKeyManager.register(settings: coordinator.settings)
                    EaveHaptics.tap()
                    withAnimation(EaveMotion.microSpring) {
                        restoredFeedback = true
                    }
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        withAnimation(EaveMotion.hover) {
                            restoredFeedback = false
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: restoredFeedback ? "checkmark" : "arrow.counterclockwise")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(restoredFeedback ? "Defaults Restored" : "Restore Default Shortcuts")
                    }
                }
                .buttonStyle(EaveSecondaryButtonStyle())

                Spacer()
            }
        }
    }
}

// MARK: - Permissions Tab

private struct PermissionsSettingsTab: View {
    let coordinator: AppCoordinator
    @State private var refreshSpin = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            EavePageHeader(
                title: "Permissions",
                subtitle: "Menu bar hiding works with zero permissions. Grant access only for advanced signals."
            )

            EaveSettingsCard("System Privacy") {
                permissionRow(
                    title: "Accessibility",
                    granted: coordinator.permissions.hasAccessibility,
                    description: "Unlocks hidden-app Dock badge detection, menu bar AX monitoring, and cursor-free click forwarding.",
                    onRequest: { coordinator.permissions.requestAccessibilityPrompt() },
                    onOpenSettings: { coordinator.permissions.openAccessibilitySettings() }
                )

                EaveCardDivider()

                permissionRow(
                    title: "Screen Recording",
                    badgeSuffix: "Optional",
                    granted: coordinator.permissions.hasScreenRecording,
                    description: "Only needed for raw pixel menu bar captures. By default, Eave renders crisp native App Icons with zero screen capture.",
                    onRequest: { coordinator.permissions.requestScreenRecordingPrompt() },
                    onOpenSettings: { coordinator.permissions.openScreenRecordingSettings() }
                )
            }

            HStack(spacing: 12) {
                Button {
                    coordinator.permissions.refresh()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.76)) {
                        refreshSpin += 1
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(Double(refreshSpin) * 360))
                        Text("Refresh Status")
                    }
                }
                .buttonStyle(EaveSecondaryButtonStyle())

                Spacer()

                Text("100% local · Zero telemetry")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear {
            coordinator.permissions.refresh()
        }
    }

    private func permissionRow(
        title: String,
        badgeSuffix: String? = nil,
        granted: Bool,
        description: String,
        onRequest: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))

                if let badgeSuffix {
                    Text(badgeSuffix)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(
                            granted
                                ? Color(red: 0.20, green: 0.72, blue: 0.42)
                                : Color(red: 0.90, green: 0.56, blue: 0.18)
                        )
                        .frame(width: 6, height: 6)
                    Text(granted ? "Granted" : "Not Granted")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text(description)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !granted {
                HStack(spacing: 8) {
                    Button("Request Access", action: onRequest)
                        .buttonStyle(EaveProminentButtonStyle())
                    Button("Open System Settings", action: onOpenSettings)
                        .buttonStyle(EaveSecondaryButtonStyle())
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
    }
}

// MARK: - Bridge Tab

private struct BridgeSettingsTab: View {
    let coordinator: AppCoordinator
    @Bindable var settings: EaveSettings
    @State private var copiedURL = false
    @State private var copiedNotif = false

    private let sampleURL = "open -g \"eave://notify?title=Build+Succeeded&subtitle=eave+0.1&badge=OK&symbol=checkmark.circle.fill\""

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self._settings = Bindable(coordinator.settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            EavePageHeader(
                title: "NotchBridge",
                subtitle: "Push peeks and ambient indicators from shell scripts, CLIs, or local macOS apps."
            )

            EaveSettingsCard("Local Protocol") {
                EaveSettingsToggleRow(
                    "Enable NotchBridge",
                    subtitle: "Accepts local eave:// URL Scheme and DistributedNotification payloads.",
                    isOn: $settings.enableNotchBridge
                )

                EaveCardDivider()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("URL Scheme")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        copyButton(isCopied: copiedURL) {
                            copyToClipboard(sampleURL)
                            triggerCopied($copiedURL)
                        }
                    }

                    Text(sampleURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.86))
                        .textSelection(.enabled)
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.6)
                                )
                        )

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("DistributedNotification")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(NotchBridge.distributedNotificationName.rawValue)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(.primary.opacity(0.85))
                                .textSelection(.enabled)
                        }
                        Spacer()
                        copyButton(isCopied: copiedNotif) {
                            copyToClipboard(NotchBridge.distributedNotificationName.rawValue)
                            triggerCopied($copiedNotif)
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(14)
            }

            EaveSettingsCard("Simulator") {
                HStack(spacing: 8) {
                    Button("Test Peek") {
                        if let url = URL(string: "eave://notify?id=demo&title=Build+Succeeded&subtitle=NotchBridge+is+ready&badge=OK&symbol=checkmark") {
                            coordinator.handleIncomingURL(url)
                        }
                    }
                    .buttonStyle(EaveProminentButtonStyle())

                    Button("Test Ambient") {
                        if let url = URL(string: "eave://notify?id=demo-ambient&mode=ambient&title=Agent+Running&badge=1") {
                            coordinator.handleIncomingURL(url)
                        }
                    }
                    .buttonStyle(EaveSecondaryButtonStyle())

                    Button("Clear") {
                        if let url = URL(string: "eave://clear?id=demo-ambient") {
                            coordinator.handleIncomingURL(url)
                        }
                    }
                    .buttonStyle(EaveSecondaryButtonStyle())

                    Spacer()
                }
                .padding(14)
            }
        }
    }

    private func copyButton(isCopied: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .medium))
                Text(isCopied ? "Copied" : "Copy")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isCopied ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isCopied ? 0.10 : 0.045))
            )
        }
        .buttonStyle(EaveTactileButtonStyle(pressedScale: 0.94))
        .animation(EaveMotion.microSpring, value: isCopied)
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        EaveHaptics.tap()
    }

    private func triggerCopied(_ flag: Binding<Bool>) {
        withAnimation(EaveMotion.microSpring) {
            flag.wrappedValue = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(EaveMotion.hover) {
                flag.wrappedValue = false
            }
        }
    }
}
