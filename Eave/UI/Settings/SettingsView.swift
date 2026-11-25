import AppKit
import SwiftUI

/// Main macOS Settings window for Eave covering General, Notch, Shortcuts, Permissions, and NotchBridge.
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
            case .permissions: "lock.shield"
            case .bridge: "bolt.horizontal"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab(coordinator: coordinator)
                .tabItem { Label(SettingsTab.general.rawValue, systemImage: SettingsTab.general.symbol) }
                .tag(SettingsTab.general)

            NotchSettingsTab(coordinator: coordinator)
                .tabItem { Label(SettingsTab.notch.rawValue, systemImage: SettingsTab.notch.symbol) }
                .tag(SettingsTab.notch)

            ShortcutsSettingsTab(coordinator: coordinator)
                .tabItem { Label(SettingsTab.shortcuts.rawValue, systemImage: SettingsTab.shortcuts.symbol) }
                .tag(SettingsTab.shortcuts)

            PermissionsSettingsTab(coordinator: coordinator)
                .tabItem { Label(SettingsTab.permissions.rawValue, systemImage: SettingsTab.permissions.symbol) }
                .tag(SettingsTab.permissions)

            BridgeSettingsTab(coordinator: coordinator)
                .tabItem { Label(SettingsTab.bridge.rawValue, systemImage: SettingsTab.bridge.symbol) }
                .tag(SettingsTab.bridge)
        }
        .frame(width: 560, height: 470)
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
                            .frame(width: 32, alignment: .trailing)
                    }
                }

                Toggle("Rehide when switching applications", isOn: $settings.rehideOnAppSwitch)
                Toggle("Scroll on menu bar to expand / collapse", isOn: $settings.expandOnMenuBarScroll)
                Toggle("Hover over right menu bar to expand", isOn: $settings.expandOnMenuBarHover)
            }

            Section("Menu Bar Spacing (System-Wide)") {
                HStack {
                    Text("Icon spacing")
                    Slider(value: $spacingValue, in: 4...20, step: 1)
                    Text("\(Int(spacingValue))pt")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }

                HStack {
                    Text("Selection padding")
                    Slider(value: $paddingValue, in: 2...16, step: 1)
                    Text("\(Int(paddingValue))pt")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }

                HStack {
                    Button("Apply Spacing") {
                        coordinator.spacingManager.apply(
                            spacing: Int(spacingValue),
                            selectionPadding: Int(paddingValue)
                        )
                    }
                    Button("Reset to System Default") {
                        coordinator.spacingManager.resetToSystemDefault()
                        spacingValue = 10
                        paddingValue = 8
                    }
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

    var body: some View {
        Form {
            Section("Notch Presentation") {
                Toggle("Peek hidden app notifications from Notch", isOn: $settings.enableNotchPeek)
                Toggle("Show ambient status dots on Notch edge", isOn: $settings.enableAmbientIndicators)
                    .onChange(of: settings.enableAmbientIndicators) { _, _ in
                        coordinator.signalHub.syncSettings()
                    }
                Toggle("Watch hidden menu-bar-only app status changes (AX)", isOn: $settings.enableMenuBarAXWatcher)
                    .onChange(of: settings.enableMenuBarAXWatcher) { _, _ in
                        coordinator.signalHub.syncSettings()
                    }
                Toggle("Use live menu bar icon capture in Notch Bar", isOn: $settings.enableLiveIconCapture)

                HStack {
                    Text("Peek duration")
                    Slider(value: $settings.peekDurationSeconds, in: 2...10, step: 0.5)
                    Text(String(format: "%.1fs", settings.peekDurationSeconds))
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }

                HStack(spacing: 10) {
                    Button("Send Test Peek") {
                        coordinator.signalHub.sendTestPeek()
                    }
                    Button("Toggle Notch Bar") {
                        coordinator.toggleNotchBar()
                    }
                }
            }

            Section("Watched Applications") {
                Toggle("Automatically watch apps hidden under Eave", isOn: $settings.watchHiddenAppsAutomatically)

                HStack {
                    TextField("Add bundle ID (e.g. com.tinyspeck.slackmacgap)", text: $newBundleID)
                    Button("Add") {
                        settings.addWatchedBundleID(newBundleID)
                        newBundleID = ""
                    }
                    .disabled(newBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !settings.watchedBundleIDs.isEmpty {
                    ForEach(settings.watchedBundleIDs, id: \.self) { bundleID in
                        HStack {
                            Text(bundleID)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button(role: .destructive) {
                                settings.removeWatchedBundleID(bundleID)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                let autoCount = coordinator.signalHub.discoveredHiddenBundleIDs.count
                Text("Currently tracking \(autoCount) auto-discovered hidden app(s).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
                    description: "Captures on-demand single frames of hidden menu bar icons inside Notch Bar. Without it, Eave gracefully displays app icons instead.",
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
                    Button("Open System Settings", action: onOpenSettings)
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
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
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

                    Button("Test Ambient Dot") {
                        if let url = URL(string: "eave://notify?id=demo-ambient&mode=ambient&title=Agent+Running&badge=1&accent=38BDF8") {
                            coordinator.handleIncomingURL(url)
                        }
                    }

                    Button("Clear Demo") {
                        if let url = URL(string: "eave://clear?id=demo-ambient") {
                            coordinator.handleIncomingURL(url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
