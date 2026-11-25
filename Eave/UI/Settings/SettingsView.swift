import AppKit
import SwiftUI

/// Modern macOS System Settings–inspired sidebar interface for Eave.
struct SettingsView: View {
    let coordinator: AppCoordinator

    @State private var selectedTab: SettingsTab = .general

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
            case .permissions: "lock.shield.fill"
            case .bridge: "bolt.horizontal.fill"
            }
        }

        var tint: Color {
            switch self {
            case .general: Color(red: 0.36, green: 0.56, blue: 0.98)
            case .notch: Color(red: 0.58, green: 0.42, blue: 0.98)
            case .shortcuts: Color(red: 0.96, green: 0.54, blue: 0.24)
            case .permissions: Color(red: 0.24, green: 0.78, blue: 0.46)
            case .bridge: Color(red: 0.16, green: 0.72, blue: 0.88)
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 184)
                .background(.ultraThinMaterial)

            Divider()

            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 680, height: 500)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Brand header with minimalist Eave app icon
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
                        .font(.system(size: 14, weight: .semibold))
                    Text("v0.1.0")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 36)
            .padding(.bottom, 14)

            ForEach(SettingsTab.allCases) { tab in
                sidebarRow(tab)
            }

            Spacer()

            // Quick status pill at sidebar bottom
            HStack(spacing: 6) {
                Circle()
                    .fill(coordinator.permissions.hasAccessibility ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(coordinator.permissions.hasAccessibility ? "Full Access" : "Basic Mode")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    private func sidebarRow(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tab.tint.gradient)
                        .frame(width: 22, height: 22)
                    Image(systemName: tab.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.09) : Color.clear)
            )
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self._settings = Bindable(coordinator.settings)
    }

    var body: some View {
        Form {
            Section("Startup & Sections") {
                Toggle("Launch Eave at login", isOn: Binding(
                    get: { coordinator.launchAtLogin.isEnabled },
                    set: { coordinator.launchAtLogin.setEnabled($0) }
                ))

                Toggle("Enable Always-Hidden section (⌥ + Click)", isOn: $settings.enableAlwaysHiddenSection)
                    .onChange(of: settings.enableAlwaysHiddenSection) { _, _ in
                        coordinator.menuBarManager.syncConfiguration()
                    }

                Toggle("Open Notch Bar on primary click", isOn: $settings.useNotchBarOnToggle)
            }

            Section("Auto-Rehide & Gestures") {
                Toggle("Automatically rehide expanded items", isOn: $settings.rehideAutomatically)

                if settings.rehideAutomatically {
                    HStack {
                        Text("Rehide delay")
                        Slider(value: $settings.rehideDelaySeconds, in: 3...20, step: 1)
                        Text("\(Int(settings.rehideDelaySeconds))s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }

                Toggle("Rehide when switching applications", isOn: $settings.rehideOnAppSwitch)
                Toggle("Scroll on menu bar to expand / collapse", isOn: $settings.expandOnMenuBarScroll)
                Toggle("Hover over right menu bar to expand", isOn: $settings.expandOnMenuBarHover)
            }

            Section("Menu Bar Spacing") {
                HStack {
                    Text("Icon spacing")
                    Slider(value: $spacingValue, in: 4...20, step: 1)
                    Text("\(Int(spacingValue))pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }

                HStack {
                    Text("Selection padding")
                    Slider(value: $paddingValue, in: 2...16, step: 1)
                    Text("\(Int(paddingValue))pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }

                HStack {
                    Button("Apply Spacing") {
                        coordinator.spacingManager.apply(
                            spacing: Int(spacingValue),
                            selectionPadding: Int(paddingValue)
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Reset Default") {
                        coordinator.spacingManager.resetToSystemDefault()
                        spacingValue = 10
                        paddingValue = 8
                    }
                    .controlSize(.small)

                    Spacer()
                }
                Text("Apps apply updated spacing after relaunch or next login.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            coordinator.spacingManager.reload()
            if let s = coordinator.spacingManager.config.spacing { spacingValue = Double(s) }
            if let p = coordinator.spacingManager.config.selectionPadding { paddingValue = Double(p) }
        }
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
        Form {
            Section("Notch Presentation") {
                Toggle("Peek hidden app notifications from Notch", isOn: $settings.enableNotchPeek)
                Toggle("Show ambient status wings on Notch", isOn: $settings.enableAmbientIndicators)
                    .onChange(of: settings.enableAmbientIndicators) { _, _ in
                        coordinator.signalHub.syncSettings()
                    }
                Toggle("Watch hidden menu-bar-only app status changes", isOn: $settings.enableMenuBarAXWatcher)
                    .onChange(of: settings.enableMenuBarAXWatcher) { _, _ in
                        coordinator.signalHub.syncSettings()
                    }
                Toggle("Use raw live menu bar pixel capture (off = crisp App Icons)", isOn: $settings.enableLiveIconCapture)

                HStack {
                    Text("Peek duration")
                    Slider(value: $settings.peekDurationSeconds, in: 2...10, step: 0.5)
                    Text(String(format: "%.1fs", settings.peekDurationSeconds))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }

                HStack(spacing: 10) {
                    Button("Preview Notch Peek") {
                        coordinator.signalHub.sendTestPeek()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Toggle Notch Bar") {
                        coordinator.toggleNotchBar()
                    }
                    .controlSize(.small)
                }
            }

            Section("Watched Applications") {
                Toggle("Automatically watch apps hidden under Eave", isOn: $settings.watchHiddenAppsAutomatically)

                HStack {
                    Menu {
                        ForEach(runningRegularApps, id: \.processIdentifier) { app in
                            if let id = app.bundleIdentifier {
                                Button(app.localizedName ?? id) {
                                    settings.addWatchedBundleID(id)
                                }
                            }
                        }
                    } label: {
                        Label("Add Running App", systemImage: "plus.app")
                    }
                    .menuStyle(.borderedButton)
                    .fixedSize()

                    TextField("or bundle ID...", text: $newBundleID)
                        .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        settings.addWatchedBundleID(newBundleID)
                        newBundleID = ""
                    }
                    .disabled(newBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !settings.watchedBundleIDs.isEmpty {
                    ForEach(settings.watchedBundleIDs, id: \.self) { bundleID in
                        watchedAppRow(bundleID: bundleID)
                    }
                }

                let autoCount = coordinator.signalHub.discoveredHiddenBundleIDs.count
                Text("Tracking \(autoCount) auto-discovered hidden app(s) + \(settings.watchedBundleIDs.count) pinned.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func watchedAppRow(bundleID: String) -> some View {
        let resolved = AppIconService.shared.resolve(
            bundleIdentifier: bundleID,
            fallbackSymbol: "app.fill",
            fallbackAccentHex: nil
        )
        let appName = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { $0.deletingPathExtension().lastPathComponent } ?? bundleID

        return HStack(spacing: 10) {
            if let img = resolved.image {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "app.fill")
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(appName)
                    .font(.system(size: 12.5, weight: .medium))
                Text(bundleID)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                settings.removeWatchedBundleID(bundleID)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Shortcuts Tab

private struct ShortcutsSettingsTab: View {
    let coordinator: AppCoordinator

    var body: some View {
        Form {
            Section("Global Keyboard Shortcuts") {
                ForEach(HotKeyAction.allCases) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        HotKeyRecorderView(combo: coordinator.settings.hotKey(for: action)) { newCombo in
                            coordinator.settings.setHotKey(newCombo, for: action)
                            coordinator.hotKeyManager.register(action: action, combo: newCombo)
                        }
                    }
                }
            }

            Section {
                Button("Restore Default Shortcuts") {
                    coordinator.settings.resetHotKeys()
                    coordinator.hotKeyManager.register(settings: coordinator.settings)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Permissions Tab

private struct PermissionsSettingsTab: View {
    let coordinator: AppCoordinator

    var body: some View {
        Form {
            Section("Privacy Permissions") {
                permissionRow(
                    title: "Accessibility",
                    granted: coordinator.permissions.hasAccessibility,
                    description: "Enables hidden-app Dock badge detection, menu bar AX monitoring, and cursor-free click forwarding.",
                    onRequest: { coordinator.permissions.requestAccessibilityPrompt() },
                    onOpenSettings: { coordinator.permissions.openAccessibilitySettings() }
                )

                permissionRow(
                    title: "Screen Recording (Optional)",
                    granted: coordinator.permissions.hasScreenRecording,
                    description: "Only needed if you opt into raw pixel menu bar captures. By default, Eave renders crisp native App Icons with zero screen capture.",
                    onRequest: { coordinator.permissions.requestScreenRecordingPrompt() },
                    onOpenSettings: { coordinator.permissions.openScreenRecordingSettings() }
                )
            }

            Section {
                HStack {
                    Button("Refresh Status") {
                        coordinator.permissions.refresh()
                    }
                    Spacer()
                    Text("Core menu bar hiding works with zero permissions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            coordinator.permissions.refresh()
        }
    }

    private func permissionRow(
        title: String,
        granted: Bool,
        description: String,
        onRequest: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Label(
                    granted ? "Granted" : "Not Granted",
                    systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(granted ? .green : .orange)
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !granted {
                HStack(spacing: 8) {
                    Button("Request Access", action: onRequest)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Open System Settings", action: onOpenSettings)
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Bridge Tab

private struct BridgeSettingsTab: View {
    let coordinator: AppCoordinator
    @Bindable var settings: EaveSettings

    private let sampleURL = "open -g \"eave://notify?title=Build+Succeeded&subtitle=eave+0.1&badge=OK&symbol=checkmark.circle.fill\""

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self._settings = Bindable(coordinator.settings)
    }

    var body: some View {
        Form {
            Section("NotchBridge Local Protocol") {
                Toggle("Enable NotchBridge (URL Scheme & DistributedNotification)", isOn: $settings.enableNotchBridge)

                Text("Send notifications from your own scripts, CLI tools, or macOS apps directly into Eave's Notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("URL Scheme Example")
                        .font(.caption.weight(.semibold))
                    Text(sampleURL)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("DistributedNotification Name")
                        .font(.caption.weight(.semibold))
                    Text(NotchBridge.distributedNotificationName.rawValue)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            Section("Quick Test") {
                HStack(spacing: 10) {
                    Button("Test Bridge Peek") {
                        if let url = URL(string: "eave://notify?id=demo&title=Build+Succeeded&subtitle=NotchBridge+is+ready&badge=OK&symbol=checkmark.circle.fill&accent=34D399") {
                            coordinator.handleIncomingURL(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Test Ambient Wing") {
                        if let url = URL(string: "eave://notify?id=demo-ambient&mode=ambient&title=Agent+Running&badge=1&accent=38BDF8") {
                            coordinator.handleIncomingURL(url)
                        }
                    }
                    .controlSize(.small)

                    Button("Clear Demo") {
                        if let url = URL(string: "eave://clear?id=demo-ambient") {
                            coordinator.handleIncomingURL(url)
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
    }
}
