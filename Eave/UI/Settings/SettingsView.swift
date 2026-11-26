import AppKit
import SwiftUI

/// Restrained, monochrome editorial Settings studio for Eave (Apple Studio / Linear aesthetic).
/// Synchronizes Light / Dark / System appearance live across sidebar, canvas, cards, and nested trays.
struct SettingsView: View {
    let coordinator: AppCoordinator

    @State private var selectedTab: SettingsTab = .general
    @State private var hoveredTab: SettingsTab?
    @State private var isStatusHovered = false
    @Namespace private var sidebarNamespace
    @Environment(\.colorScheme) private var systemColorScheme

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case notch = "Notch"
        case shortcuts = "Shortcuts"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .general: "slider.horizontal.3"
            case .notch: "macbook"
            case .shortcuts: "command"
            }
        }
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var effectiveColorScheme: ColorScheme {
        coordinator.settings.appearanceMode.colorScheme ?? systemColorScheme
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 196)
                .background(EavePalette.sidebar(effectiveColorScheme))

            Rectangle()
                .fill(EavePalette.divider(effectiveColorScheme))
                .frame(width: 0.65)

            ScrollView {
                detailPane
                    .padding(.horizontal, 26)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(selectedTab)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(EavePalette.canvas(effectiveColorScheme))
        }
        .frame(width: 720, height: 540)
        .preferredColorScheme(coordinator.settings.appearanceMode.colorScheme)
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
                    Text("Version \(Self.appVersion)")
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

            // Quiet Accessibility status pill
            Button {
                if coordinator.permissions.hasAccessibility {
                    coordinator.permissions.refresh()
                } else {
                    coordinator.permissions.requestAccessibilityPrompt()
                    coordinator.permissions.openAccessibilitySettings()
                }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(
                            coordinator.permissions.hasAccessibility
                                ? Color(red: 0.20, green: 0.72, blue: 0.42)
                                : Color(red: 0.90, green: 0.56, blue: 0.18)
                        )
                        .frame(width: 6.5, height: 6.5)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(coordinator.permissions.hasAccessibility ? "Accessibility On" : "Grant Accessibility")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.84))
                        Text(coordinator.permissions.hasAccessibility ? "All signals active" : "Required for badges & clicks")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 2)

                    if !coordinator.permissions.hasAccessibility {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                        .fill(Color.primary.opacity(isStatusHovered ? 0.065 : 0.032))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                        .strokeBorder(EavePalette.insetBorder(effectiveColorScheme), lineWidth: 0.6)
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

        return Button {
            if selectedTab != tab {
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
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7.5)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.085))
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
        }
    }
}

// MARK: - General Tab

private struct GeneralSettingsTab: View {
    let coordinator: AppCoordinator
    @Bindable var settings: EaveSettings
    @Environment(\.colorScheme) private var colorScheme

    @State private var showSpacingOptions = false
    @State private var spacingValue: Double = 10
    @State private var paddingValue: Double = 8
    @State private var appliedFeedback = false

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self._settings = Bindable(coordinator.settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            EavePageHeader(
                title: "General",
                subtitle: "Appearance, hover reveal behavior, and menu bar housekeeping."
            )

            appearanceAndStartupCard
            hoverRevealCard
            menuBarDensityCard
            privacyCard
        }
        .onAppear {
            coordinator.permissions.refresh()
            coordinator.spacingManager.reload()
            if let s = coordinator.spacingManager.config.spacing { spacingValue = Double(s) }
            if let p = coordinator.spacingManager.config.selectionPadding { paddingValue = Double(p) }
        }
    }

    private var appearanceAndStartupCard: some View {
        EaveSettingsCard("Appearance & Startup") {
            EaveSettingsSegmentedRow(
                "Appearance",
                subtitle: "Match macOS automatically or lock Eave to Light / Dark.",
                selection: $settings.appearanceMode,
                pickerWidth: 196
            ) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .onChange(of: settings.appearanceMode) { _, _ in
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
                "Auto-rehide expanded items",
                subtitle: "Collapses automatically after 8s of inactivity or when switching apps.",
                isOn: $settings.rehideAutomatically
            )

            EaveCardDivider()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick Start Guide")
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                    Text("Revisit the interactive walkthrough for hiding icons, hover reveal, and Notch signals.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button("Open Guide") {
                    coordinator.openOnboardingWindow()
                }
                .buttonStyle(EaveSecondaryButtonStyle(compact: true))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }

    private var hoverRevealCard: some View {
        EaveSettingsCard("Hover Reveal") {
            EaveSettingsToggleRow(
                "Hover Eave icon to reveal hidden items",
                subtitle: "Rest your pointer over the Eave menu bar icon to inspect hidden apps.",
                isOn: $settings.expandOnEaveHover.animation(EaveMotion.microSpring)
            )
            .onChange(of: settings.expandOnEaveHover) { _, _ in
                coordinator.syncHoverSettings()
            }

            if settings.expandOnEaveHover {
                hoverRevealSubSection
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            }
        }
    }

    private var hoverRevealSubSection: some View {
        EaveSettingsSubSection {
            EaveSettingsSegmentedRow(
                "Display style",
                subtitle: settings.hoverDisplayMode == .secondRow
                    ? "Float hidden icons in a clean second row below the menu bar."
                    : "Expand hidden items inline inside the macOS menu bar.",
                selection: $settings.hoverDisplayMode.animation(EaveMotion.microSpring),
                pickerWidth: 176,
                inset: true
            ) {
                ForEach(HoverDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .onChange(of: settings.hoverDisplayMode) { _, _ in
                coordinator.syncHoverSettings()
            }

            EaveCardDivider(leadingInset: 12)

            EaveSettingsSliderRow(
                "Hover delay",
                subtitle: "Time pointer rests on the Eave icon before opening.",
                value: $settings.hoverDelaySeconds,
                in: 0.10...0.60,
                step: 0.05,
                valueText: String(format: "%.2fs", settings.hoverDelaySeconds),
                inset: true
            )

            if settings.hoverDisplayMode == .secondRow {
                secondRowLayoutSubControls
            }
        }
    }

    @ViewBuilder
    private var secondRowLayoutSubControls: some View {
        EaveCardDivider(leadingInset: 12)

        EaveSettingsSegmentedRow(
            "Overflow layout",
            subtitle: settings.secondRowLayoutMode == .horizontalScroll
                ? "Single sleek row with horizontal swipe."
                : "Automatically wrap extra icons onto new rows.",
            selection: $settings.secondRowLayoutMode.animation(EaveMotion.microSpring),
            pickerWidth: 196,
            inset: true
        ) {
            ForEach(SecondRowLayoutMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .onChange(of: settings.secondRowLayoutMode) { _, _ in
            coordinator.syncHoverSettings()
        }

        EaveCardDivider(leadingInset: 12)

        EaveSettingsSliderRow(
            "Items per row",
            value: Binding(
                get: { Double(settings.secondRowItemsPerRow) },
                set: { settings.secondRowItemsPerRow = Int($0.rounded()) }
            ),
            in: Double(EaveSettings.secondRowItemsPerRowRange.lowerBound)...Double(EaveSettings.secondRowItemsPerRowRange.upperBound),
            step: 1,
            valueText: "\(settings.secondRowItemsPerRow) / row",
            inset: true
        )
        .onChange(of: settings.secondRowItemsPerRow) { _, _ in
            coordinator.syncHoverSettings()
        }

        secondRowPreviewStage
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .padding(.bottom, 12)
    }

    private var menuBarDensityCard: some View {
        EaveSettingsCard("Menu Bar Density") {
            Button {
                withAnimation(EaveMotion.microSpring) {
                    showSpacingOptions.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("System icon spacing")
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                        Text("Adjust the gap between menu bar icons. Apps update after relaunch; system icons after you log out.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(spacingValue))pt · \(Int(paddingValue))pt")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showSpacingOptions ? 90 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showSpacingOptions {
                spacingSubSection
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            }
        }
    }

    private var spacingSubSection: some View {
        EaveSettingsSubSection {
            menuBarSpacingPreview
                .padding(.horizontal, 12)
                .padding(.top, 11)
                .padding(.bottom, 4)

            EaveSettingsSliderRow(
                "Icon spacing",
                value: $spacingValue,
                in: 4...20,
                step: 1,
                valueText: "\(Int(spacingValue)) pt",
                inset: true
            )

            EaveCardDivider(leadingInset: 12)

            EaveSettingsSliderRow(
                "Selection padding",
                value: $paddingValue,
                in: 2...16,
                step: 1,
                valueText: "\(Int(paddingValue)) pt",
                inset: true
            )

            HStack(spacing: 8) {
                Button {
                    coordinator.spacingManager.apply(
                        spacing: Int(spacingValue),
                        selectionPadding: Int(paddingValue)
                    )
                    withAnimation(EaveMotion.microSpring) {
                        appliedFeedback = true
                    }
                    Task {
                        try? await Task.sleep(nanoseconds: 2_600_000_000)
                        withAnimation(EaveMotion.hover) {
                            appliedFeedback = false
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        if appliedFeedback {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
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
            .padding(.horizontal, 12)
            .padding(.top, 4)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)
                Text("Third-party apps pick up new spacing after relaunching. Built-in macOS menu bar items (Wi-Fi, Battery, Clock) require logging out and signing back in.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private var privacyCard: some View {
        EaveSettingsCard("Privacy") {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2.5) {
                    HStack(spacing: 7) {
                        Text("Accessibility")
                            .font(.system(size: 13, weight: .medium))
                        HStack(spacing: 4.5) {
                            Circle()
                                .fill(
                                    coordinator.permissions.hasAccessibility
                                        ? Color(red: 0.20, green: 0.72, blue: 0.42)
                                        : Color(red: 0.90, green: 0.56, blue: 0.18)
                                )
                                .frame(width: 6, height: 6)
                            Text(coordinator.permissions.hasAccessibility ? "Granted" : "Not Granted")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(EavePalette.pillFill(colorScheme)))
                    }

                    Text("Enables hidden-app discovery, Dock badge alerts, and menu-bar click forwarding. 100% local.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if coordinator.permissions.hasAccessibility {
                    Button("Refresh") {
                        coordinator.permissions.refresh()
                    }
                    .buttonStyle(EaveSecondaryButtonStyle(compact: true))
                } else {
                    HStack(spacing: 6) {
                        Button("Grant") {
                            coordinator.permissions.requestAccessibilityPrompt()
                        }
                        .buttonStyle(EaveProminentButtonStyle())
                        Button("Settings") {
                            coordinator.permissions.openAccessibilitySettings()
                        }
                        .buttonStyle(EaveSecondaryButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }

    private var secondRowPreviewStage: some View {
        let sampleSymbols = [
            "bubble.left", "cloud", "network", "lock.shield", "terminal",
            "music.note", "tray", "calendar", "bolt", "paperplane",
            "waveform", "globe", "gearshape", "sparkles", "cpu", "antenna.radiowaves.left.and.right"
        ]
        let sampleCount = max(settings.secondRowItemsPerRow + 4, 12)
        let previewItems = Array(sampleSymbols.prefix(min(sampleCount, sampleSymbols.count)))
        let visibleViewportWidth = CGFloat(settings.secondRowItemsPerRow) * 24
            + CGFloat(max(settings.secondRowItemsPerRow - 1, 0)) * 5

        return VStack(alignment: .leading, spacing: 8) {
            // Subtle simulated menu bar top edge with Eave anchor dot on the right
            HStack(spacing: 6) {
                Text(
                    settings.secondRowLayoutMode == .horizontalScroll
                        ? "Live Layout · \(settings.secondRowItemsPerRow) visible, swipe ↔"
                        : "Live Layout · wraps at \(settings.secondRowItemsPerRow) per row"
                )
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    coordinator.showSecondRowBar(pinnedForPreview: true)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text("Preview")
                    }
                }
                .buttonStyle(EaveSecondaryButtonStyle(compact: true))
            }

            // Floating card miniature aligned toward trailing edge like the real Second Row
            HStack {
                Spacer(minLength: 0)
                Group {
                    if settings.secondRowLayoutMode == .horizontalScroll {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(Array(previewItems.enumerated()), id: \.offset) { _, symbol in
                                    previewCell(symbol)
                                }
                            }
                        }
                        .frame(maxWidth: min(visibleViewportWidth, 380), alignment: .leading)
                    } else {
                        let rows = SecondRowLayoutMetrics.chunkedRows(previewItems, itemsPerRow: settings.secondRowItemsPerRow)
                        ScrollView(.horizontal, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                    HStack(spacing: 5) {
                                        ForEach(Array(row.enumerated()), id: \.offset) { _, symbol in
                                            previewCell(symbol)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(EavePalette.cardFill(colorScheme))
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.07), radius: 5, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(EavePalette.cardBorder(colorScheme), lineWidth: 0.65)
                )
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.025) : Color.black.opacity(0.022))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(EavePalette.insetBorder(colorScheme), lineWidth: 0.55)
        )
    }

    private func previewCell(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.primary.opacity(0.76))
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(EavePalette.pillFill(colorScheme))
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
                                .fill(index == 2 ? Color.primary.opacity(0.10) : Color.clear)
                        )
                }
            }
            .animation(EaveMotion.microSpring, value: spacingValue)
            .animation(EaveMotion.microSpring, value: paddingValue)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                .fill(EavePalette.cardFill(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                .strokeBorder(EavePalette.cardBorder(colorScheme), lineWidth: 0.6)
        )
    }
}

// MARK: - Notch Tab

private struct NotchSettingsTab: View {
    let coordinator: AppCoordinator
    @Bindable var settings: EaveSettings
    @Environment(\.colorScheme) private var colorScheme

    @State private var newBundleID: String = ""
    @State private var showBridgeDetails = false
    @State private var copiedURL = false
    @State private var copiedNotif = false

    private let sampleURL = "open -g \"eave://notify?id=demo&symbol=sparkles&accent=%2334C759&url=eave://settings\""

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
        VStack(alignment: .leading, spacing: 18) {
            EavePageHeader(
                title: "Notch",
                subtitle: "Quiet alerts and ongoing indicators shown around the top center of your screen."
            )

            notchPreviewStage
            notificationsCard
            watchedAppsCard
            notchBridgeCard
        }
    }

    private var notificationsCard: some View {
        EaveSettingsCard("Notifications") {
            EaveSettingsToggleRow(
                "Show hidden app notifications",
                subtitle: "Briefly shows the app icon and unread count when a hidden or watched app gets a new badge.",
                isOn: $settings.enableNotchPeek.animation(EaveMotion.microSpring)
            )
            .onChange(of: settings.enableNotchPeek) { _, _ in
                coordinator.signalHub.syncSettings()
            }

            if settings.enableNotchPeek {
                EaveSettingsSubSection {
                    EaveSettingsSliderRow(
                        "Alert duration",
                        subtitle: "How long a notch alert stays visible before it hides.",
                        value: $settings.peekDurationSeconds,
                        in: 2.0...10.0,
                        step: 0.5,
                        valueText: String(format: "%.1fs", settings.peekDurationSeconds),
                        inset: true
                    )
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            }
        }
    }

    private var watchedAppsCard: some View {
        EaveSettingsCard("Watched Applications") {
            EaveSettingsToggleRow(
                "Automatically watch hidden apps",
                subtitle: "Tracking \(coordinator.signalHub.discoveredHiddenBundleIDs.count) hidden · \(settings.watchedBundleIDs.count) pinned.",
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

                TextField("Or enter an app ID (com.example.app)…", text: $newBundleID)
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
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

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

    private var notchBridgeCard: some View {
        EaveSettingsCard("Developer · Script & App Signals", subtitle: "NotchBridge local automation API") {
            EaveSettingsToggleRow(
                "Accept signals from scripts and apps",
                subtitle: "Lets local scripts, CLIs, and apps show an icon, colored dot, or count in the notch, with an optional click link.",
                isOn: $settings.enableNotchBridge.animation(EaveMotion.microSpring)
            )

            if settings.enableNotchBridge {
                EaveCardDivider()

                Button {
                    withAnimation(EaveMotion.microSpring) {
                        showBridgeDetails.toggle()
                    }
                } label: {
                    HStack {
                        Text("Protocol & Simulator")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(showBridgeDetails ? 90 : 0))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9.5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showBridgeDetails {
                    notchBridgeDetailsSubSection
                        .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
                }
            }
        }
    }

    private var notchBridgeDetailsSubSection: some View {
        EaveSettingsSubSection {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("URL Scheme")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    copyButton(isCopied: copiedURL) {
                        copyToClipboard(sampleURL)
                        triggerCopied($copiedURL)
                    }
                }

                Text(sampleURL)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.86))
                    .textSelection(.enabled)
                    .padding(9.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(EavePalette.cardFill(colorScheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(EavePalette.cardBorder(colorScheme), lineWidth: 0.6)
                    )

                HStack {
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text("App notification name")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(NotchBridge.distributedNotificationName.rawValue)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.84))
                            .textSelection(.enabled)
                    }
                    Spacer()
                    copyButton(isCopied: copiedNotif) {
                        copyToClipboard(NotchBridge.distributedNotificationName.rawValue)
                        triggerCopied($copiedNotif)
                    }
                }

                HStack(spacing: 7) {
                    Button("Test Dot") {
                        if let url = URL(string: "eave://notify?id=demo-dot&symbol=checkmark.circle.fill&accent=%2334C759&url=eave://settings") {
                            coordinator.handleIncomingURL(url)
                        }
                    }
                    .buttonStyle(EaveProminentButtonStyle())

                    Button("Test Badge") {
                        if let url = URL(string: "eave://notify?id=demo-badge&symbol=bell.fill&badge=3&accent=%23FF453A&url=eave://settings") {
                            coordinator.handleIncomingURL(url)
                        }
                    }
                    .buttonStyle(EaveSecondaryButtonStyle())

                    Button("Test Wave") {
                        if let url = URL(string: "eave://notify?id=demo-ambient&mode=ambient&style=wave&symbol=sparkles&accent=%2338BDF8&url=eave://settings") {
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
                .padding(.top, 2)
            }
            .padding(12)
        }
    }

    private var notchPreviewStage: some View {
        VStack(spacing: 11) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(EavePalette.insetFill(colorScheme))
                    .frame(height: 62)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(EavePalette.insetBorder(colorScheme), lineWidth: 0.6)
                    )

                // Miniature hardware notch silhouette
                HStack(spacing: 0) {
                    if settings.enableNotchPeek {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.86))
                            .frame(width: 28)
                            .transition(.opacity)
                    }

                    Circle()
                        .fill(Color(white: 0.14))
                        .overlay(Circle().strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
                        .frame(width: 5.5, height: 5.5)
                        .frame(width: 82)

                    if settings.enableNotchPeek {
                        Text("3")
                            .font(EaveTypography.badgeFont(size: 11.0, weight: "Fredoka-Regular"))
                            .foregroundStyle(Color(red: 1.0, green: 0.34, blue: 0.30))
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
                                .stroke(.white.opacity(0.12), lineWidth: 0.5)
                        )
                )
                .animation(EaveMotion.notchMorph, value: settings.enableNotchPeek)
            }

            HStack(spacing: 8) {
                Button("Preview Notch Alert") {
                    coordinator.signalHub.sendTestPeek()
                }
                .buttonStyle(EaveProminentButtonStyle())
                .disabled(!settings.enableNotchPeek)

                Spacer()

                Text(settings.enableNotchPeek ? "On · alerts show for \(String(format: "%.1fs", settings.peekDurationSeconds))" : "Alerts paused")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(EavePalette.cardFill(colorScheme))
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.0 : 0.035), radius: 2.5, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(EavePalette.cardBorder(colorScheme), lineWidth: 0.65)
        )
    }

    private func copyButton(isCopied: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9.5, weight: .medium))
                Text(isCopied ? "Copied" : "Copy")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(isCopied ? .primary : .secondary)
            .padding(.horizontal, 7.5)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .fill(Color.primary.opacity(isCopied ? 0.11 : 0.05))
            )
        }
        .buttonStyle(EaveTactileButtonStyle(pressedScale: 0.94))
        .animation(EaveMotion.microSpring, value: isCopied)
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
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
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(isHovered ? .primary : .tertiary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(isHovered ? 0.08 : 0.0)))
            }
            .buttonStyle(EaveTactileButtonStyle(pressedScale: 0.88))
            .accessibilityLabel("Stop watching \(appName)")
            .help("Stop watching \(appName)")
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
        case .openSearch: "Open the keyboard-first menu bar search palette."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            EavePageHeader(
                title: "Shortcuts",
                subtitle: "Global keybindings and interaction reference."
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

            EaveSettingsCard("Interaction Guide") {
                interactionRow(gesture: "Left-click Eave", description: "Expand or collapse hidden items inline in the menu bar.")
                EaveCardDivider()
                interactionRow(gesture: "Hover Eave", description: "Reveal hidden items inline or in the floating Second Row.")
                EaveCardDivider()
                interactionRow(gesture: "Right-click icon", description: "In the Second Row, open an app's menu bar menu, e.g. Tailscale.")
                EaveCardDivider()
                interactionRow(gesture: "⌘ + Drag icon", description: "Click the Eave icon to show the • divider, then ⌘-drag icons to its left to hide them.")
            }
        }
    }

    private func interactionRow(gesture: String, description: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            EaveKeycap(label: gesture, fontSize: 10.5, horizontalPadding: 7, verticalPadding: 3)
                .frame(width: 116, alignment: .leading)

            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9.5)
    }
}
