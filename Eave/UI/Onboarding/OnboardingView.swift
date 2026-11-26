import AppKit
import SwiftUI

/// Restrained, interactive 4-step first-launch walkthrough crafted in Eave's monochrome studio language.
/// Introduces two-section menu bar hiding, hover reveal mode selection, optional Accessibility, and Notch signals.
struct OnboardingView: View {
    let coordinator: AppCoordinator
    let onFinish: () -> Void

    @Bindable var settings: EaveSettings
    @Environment(\.colorScheme) private var systemColorScheme

    @State private var currentStep: Step = .organize
    @State private var previewSentFeedback: Bool = false

    enum Step: Int, CaseIterable, Identifiable {
        case organize = 0
        case reveal = 1
        case privacy = 2
        case notch = 3

        var id: Int { rawValue }

        var shortLabel: String {
            switch self {
            case .organize: "Organize"
            case .reveal: "Reveal"
            case .privacy: "Privacy"
            case .notch: "Notch"
            }
        }

        var title: String {
            switch self {
            case .organize: "Tidy your menu bar in seconds"
            case .reveal: "Choose how hidden icons appear"
            case .privacy: "Private by design"
            case .notch: "Quiet signals around the notch"
            }
        }

        func subtitle(hasPhysicalNotch: Bool) -> String {
            switch self {
            case .organize:
                "Hold ⌘ and drag any menu bar icon to the left of Eave's dot divider to keep it out of sight."
            case .reveal:
                "Hover over the Eave icon on any display to see hidden apps without disrupting your workflow."
            case .privacy:
                "Core hiding needs zero permissions. Accessibility is optional, local-only, and Screen Recording is never requested."
            case .notch:
                hasPhysicalNotch
                    ? "When a hidden app gets a new Dock badge or a script sends a signal, Eave shows a small icon and indicator beside the camera."
                    : "When a hidden app gets a new Dock badge or a script sends a signal, Eave shows a small icon and indicator at the top center of your screen."
            }
        }

        var next: Step? { Step(rawValue: rawValue + 1) }
        var previous: Step? { Step(rawValue: rawValue - 1) }
    }

    init(coordinator: AppCoordinator, onFinish: @escaping () -> Void) {
        self.coordinator = coordinator
        self.onFinish = onFinish
        self._settings = Bindable(coordinator.settings)
    }

    private var effectiveColorScheme: ColorScheme {
        coordinator.settings.appearanceMode.colorScheme ?? systemColorScheme
    }

    private var hasPhysicalNotch: Bool {
        NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 28)
                .padding(.top, 36)
                .padding(.bottom, 15)

            Rectangle()
                .fill(EavePalette.divider(effectiveColorScheme))
                .frame(height: 0.65)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(currentStep.title)
                        .font(.system(size: 19, weight: .semibold))
                        .tracking(-0.3)
                    Text(currentStep.subtitle(hasPhysicalNotch: hasPhysicalNotch))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(1.5)
                }

                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 16)
            .id(currentStep)
            .transition(.opacity.combined(with: .offset(y: 4)))

            Rectangle()
                .fill(EavePalette.divider(effectiveColorScheme))
                .frame(height: 0.65)

            footerBar
                .padding(.horizontal, 28)
                .padding(.vertical, 15)
        }
        .frame(width: 580, height: 484)
        .background(EavePalette.canvas(effectiveColorScheme))
        .preferredColorScheme(coordinator.settings.appearanceMode.colorScheme)
        .onAppear {
            coordinator.permissions.refresh()
            coordinator.permissions.startPolling(interval: 1.5)
        }
        .onDisappear {
            coordinator.permissions.startPolling(interval: 8.0)
        }
    }

    // MARK: - Top Bar & Stepper

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 0.5) {
                    Text("Welcome to Eave")
                        .font(.system(size: 13.5, weight: .semibold))
                        .tracking(-0.15)
                    Text("Quick Start")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Clickable step pills
            HStack(spacing: 4) {
                ForEach(Step.allCases) { step in
                    let isCurrent = step == currentStep
                    let isPast = step.rawValue < currentStep.rawValue
                    Button {
                        if step != currentStep {
                            EaveHaptics.tick()
                            withAnimation(EaveMotion.tabSwitch) {
                                currentStep = step
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if isPast {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            Text(step.shortLabel)
                                .font(.system(size: 10.5, weight: isCurrent ? .semibold : .medium))
                        }
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(
                                    isCurrent
                                        ? Color.primary.opacity(0.095)
                                        : Color.primary.opacity(0.03)
                                )
                        )
                    }
                    .buttonStyle(EaveTactileButtonStyle(pressedScale: 0.96))
                }
            }
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .organize:
            organizeStepView
        case .reveal:
            revealStepView
        case .privacy:
            privacyStepView
        case .notch:
            notchStepView
        }
    }

    // MARK: Step 1 — Organize Menu Bar

    private var organizeStepView: some View {
        VStack(alignment: .leading, spacing: 14) {
            OnboardingMenuBarDemoStage(colorScheme: effectiveColorScheme)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(coordinator.menuBarManager.isHiddenExpanded ? "Divider is visible in your menu bar" : "Try it live right now")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("Reveal the • dot in your top menu bar so you can ⌘-drag apps to its left.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button(coordinator.menuBarManager.isHiddenExpanded ? "Collapse Divider" : "Reveal Divider") {
                    EaveHaptics.tap()
                    coordinator.menuBarManager.toggleHidden()
                }
                .buttonStyle(EaveSecondaryButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(EavePalette.cardFill(effectiveColorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(EavePalette.cardBorder(effectiveColorScheme), lineWidth: 0.65)
            )

            HStack(spacing: 16) {
                gestureCaption(key: "⌘ + Drag", text: "Move left of • to hide")
                gestureCaption(key: "Left-click", text: "Expand or collapse inline")
                gestureCaption(key: "Right-click", text: "Open Settings & tools")
            }
            .padding(.horizontal, 2)
        }
    }

    private func gestureCaption(key: String, text: String) -> some View {
        HStack(spacing: 6) {
            EaveKeycap(label: key, fontSize: 10, horizontalPadding: 6, verticalPadding: 2)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: Step 2 — Hover Reveal Mode

    private var revealStepView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                hoverModeOptionCard(
                    mode: .secondRow,
                    title: "Second Row",
                    badge: "Recommended",
                    description: "Floats hidden app icons in a clean shelf right below the menu bar — zero bar shifting."
                )

                hoverModeOptionCard(
                    mode: .inline,
                    title: "Inline",
                    badge: nil,
                    description: "Expands hidden icons directly inside the top macOS menu bar on hover."
                )
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Tip: Press")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                EaveKeycap(
                    label: settings.hotKey(for: .openSearch)?.displayString ?? "⌥⌘K",
                    fontSize: 10,
                    horizontalPadding: 6,
                    verticalPadding: 2
                )
                Text("anytime to fuzzy-search and click any visible or hidden menu bar item.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(EavePalette.insetFill(effectiveColorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(EavePalette.insetBorder(effectiveColorScheme), lineWidth: 0.6)
            )
        }
    }

    private func hoverModeOptionCard(
        mode: HoverDisplayMode,
        title: String,
        badge: String?,
        description: String
    ) -> some View {
        let isSelected = settings.hoverDisplayMode == mode

        return Button {
            EaveHaptics.tick()
            withAnimation(EaveMotion.microSpring) {
                settings.expandOnEaveHover = true
                settings.hoverDisplayMode = mode
            }
            coordinator.syncHoverSettings()
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                hoverModeMiniature(mode: mode)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)

                        if let badge {
                            Text(badge)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(EavePalette.pillFill(effectiveColorScheme)))
                        }

                        Spacer()

                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary.opacity(0.35))
                    }

                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(1.2)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(EavePalette.cardFill(effectiveColorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.primary.opacity(effectiveColorScheme == .dark ? 0.45 : 0.42)
                            : EavePalette.cardBorder(effectiveColorScheme),
                        lineWidth: isSelected ? 1.2 : 0.65
                    )
            )
        }
        .buttonStyle(EaveTactileButtonStyle(pressedScale: 0.985))
    }

    private func hoverModeMiniature(mode: HoverDisplayMode) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            // Top simulated menu bar strip
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                if mode == .inline {
                    ForEach(["bubble.left", "network", "cloud"], id: \.self) { sym in
                        Image(systemName: sym)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.70))
                    }
                    Circle()
                        .fill(Color.primary.opacity(0.45))
                        .frame(width: 3, height: 3)
                }
                Image(systemName: "rectangle.topthird.inset.filled")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)
                Image(systemName: "wifi")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                Image(systemName: "battery.100percent")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(EavePalette.cardFill(effectiveColorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(EavePalette.insetBorder(effectiveColorScheme), lineWidth: 0.55)
            )

            if mode == .secondRow {
                // Floating second-row shelf beneath the menu bar
                HStack(spacing: 5) {
                    ForEach(["bubble.left", "network", "cloud", "terminal"], id: \.self) { sym in
                        Image(systemName: sym)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.82))
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                    .fill(EavePalette.pillFill(effectiveColorScheme))
                            )
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(EavePalette.cardFill(effectiveColorScheme))
                        .shadow(color: Color.black.opacity(effectiveColorScheme == .dark ? 0.28 : 0.08), radius: 5, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(EavePalette.cardBorder(effectiveColorScheme), lineWidth: 0.65)
                )
                .padding(.trailing, 18)
            } else {
                Spacer(minLength: 32)
            }
        }
        .padding(10)
        .frame(height: 82)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                .fill(EavePalette.insetFill(effectiveColorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                .strokeBorder(EavePalette.insetBorder(effectiveColorScheme), lineWidth: 0.55)
        )
    }

    // MARK: Step 3 — Accessibility & Privacy

    private var privacyStepView: some View {
        let granted = coordinator.permissions.hasAccessibility

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                granted
                                    ? Color(red: 0.20, green: 0.72, blue: 0.42).opacity(0.14)
                                    : EavePalette.pillFill(effectiveColorScheme)
                            )
                            .frame(width: 34, height: 34)
                        Image(systemName: granted ? "checkmark.shield.fill" : "hand.raised.fill")
                            .font(.system(size: 14.5, weight: .medium))
                            .foregroundStyle(
                                granted
                                    ? Color(red: 0.20, green: 0.72, blue: 0.42)
                                    : .primary.opacity(0.75)
                            )
                    }

                    VStack(alignment: .leading, spacing: 2.5) {
                        HStack(spacing: 7) {
                            Text("Accessibility")
                                .font(.system(size: 13.5, weight: .semibold))
                            HStack(spacing: 4.5) {
                                Circle()
                                    .fill(
                                        granted
                                            ? Color(red: 0.20, green: 0.72, blue: 0.42)
                                            : Color(red: 0.90, green: 0.56, blue: 0.18)
                                    )
                                    .frame(width: 6, height: 6)
                                Text(granted ? "Granted" : "Optional")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(EavePalette.pillFill(effectiveColorScheme)))
                        }

                        Text(granted ? "All features active — hidden discovery, click forwarding, and Dock badges." : "Enable in System Settings → Privacy & Security → Accessibility.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    if !granted {
                        Button("Grant") {
                            EaveHaptics.tap()
                            coordinator.permissions.requestAccessibilityPrompt()
                            coordinator.permissions.openAccessibilitySettings()
                        }
                        .buttonStyle(EaveProminentButtonStyle())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)

                EaveCardDivider()

                VStack(alignment: .leading, spacing: 9) {
                    privacyBenefitRow(
                        symbol: "square.grid.2x2",
                        text: "Instant hidden-app discovery for Second Row & Quick Search"
                    )
                    privacyBenefitRow(
                        symbol: "cursorarrow.click.2",
                        text: "Left & right click forwarding to menu-bar utilities like Tailscale"
                    )
                    privacyBenefitRow(
                        symbol: "bell.badge",
                        text: "Automatic notch alerts when hidden apps get unread Dock badges"
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(EavePalette.cardFill(effectiveColorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(EavePalette.cardBorder(effectiveColorScheme), lineWidth: 0.65)
            )
            .animation(EaveMotion.microSpring, value: granted)

            HStack(spacing: 8) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Zero Screen Recording permission · Native macOS app icons only · 100% local.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9.5)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(EavePalette.insetFill(effectiveColorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(EavePalette.insetBorder(effectiveColorScheme), lineWidth: 0.6)
            )
        }
    }

    private func privacyBenefitRow(symbol: String, text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.primary.opacity(0.84))
        }
    }

    // MARK: Step 4 — Notch Signals & Launch at Login

    private var notchStepView: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(spacing: 11) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(EavePalette.insetFill(effectiveColorScheme))
                        .frame(height: 60)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(EavePalette.insetBorder(effectiveColorScheme), lineWidth: 0.6)
                        )

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
                    Button {
                        EaveHaptics.tap()
                        coordinator.signalHub.sendTestPeek()
                        withAnimation(EaveMotion.microSpring) {
                            previewSentFeedback = true
                        }
                        Task {
                            try? await Task.sleep(nanoseconds: 1_800_000_000)
                            withAnimation(EaveMotion.hover) {
                                previewSentFeedback = false
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: previewSentFeedback ? "checkmark" : "sparkles")
                                .font(.system(size: 10, weight: .semibold))
                            Text(previewSentFeedback ? "Alert Sent" : "Preview Notch Alert")
                        }
                    }
                    .buttonStyle(EaveSecondaryButtonStyle())
                    .disabled(!settings.enableNotchPeek)

                    Spacer()

                    Text("Click wings to jump straight to the app")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(EavePalette.cardFill(effectiveColorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(EavePalette.cardBorder(effectiveColorScheme), lineWidth: 0.65)
            )

            EaveSettingsCard {
                EaveSettingsToggleRow(
                    "Show hidden app notifications in Notch",
                    subtitle: "Briefly shows an alert when a hidden or watched app has unread badges.",
                    isOn: $settings.enableNotchPeek.animation(EaveMotion.microSpring)
                )
                .onChange(of: settings.enableNotchPeek) { _, _ in
                    coordinator.signalHub.syncSettings()
                }

                EaveCardDivider()

                EaveSettingsToggleRow(
                    "Launch Eave at login",
                    subtitle: "Start quietly in the menu bar whenever you sign in.",
                    isOn: Binding(
                        get: { coordinator.launchAtLogin.isEnabled },
                        set: { coordinator.launchAtLogin.setEnabled($0) }
                    )
                )
            }
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            if let prev = currentStep.previous {
                Button("Back") {
                    EaveHaptics.tick()
                    withAnimation(EaveMotion.tabSwitch) {
                        currentStep = prev
                    }
                }
                .buttonStyle(EaveSecondaryButtonStyle())
            } else {
                Button("Skip") {
                    EaveHaptics.tick()
                    onFinish()
                }
                .buttonStyle(EaveSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
            }

            Spacer()

            HStack(spacing: 5) {
                ForEach(Step.allCases) { step in
                    Capsule()
                        .fill(
                            step == currentStep
                                ? Color.primary.opacity(0.75)
                                : Color.primary.opacity(0.16)
                        )
                        .frame(width: step == currentStep ? 16 : 6, height: 5)
                        .animation(EaveMotion.microSpring, value: currentStep)
                }
            }

            Spacer()

            if let next = currentStep.next {
                Button {
                    EaveHaptics.tick()
                    withAnimation(EaveMotion.tabSwitch) {
                        currentStep = next
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(currentStep == .privacy && !coordinator.permissions.hasAccessibility ? "Skip for now" : "Continue")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(EaveProminentButtonStyle())
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Start Using Eave") {
                    EaveHaptics.tap()
                    onFinish()
                }
                .buttonStyle(EaveProminentButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - Animated Menu Bar Hiding Stage (Step 1)

private struct OnboardingMenuBarDemoStage: View {
    let colorScheme: ColorScheme

    /// 0 = expanded before drag, 1 = icon gliding left past dot, 2 = collapsed cleanly
    @State private var phase: Int = 0
    @State private var loopTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(phase == 2 ? Color.primary.opacity(0.22) : Color.primary.opacity(0.55))
                        .frame(width: 5, height: 5)
                    Text(phaseCaption)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                Spacer()
                Text(phase == 2 ? "Hidden" : "Expanded")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(EavePalette.pillFill(colorScheme)))
            }

            // Simulated macOS menu bar
            HStack(spacing: 0) {
                // Hidden section zone
                HStack(spacing: 7) {
                    if phase != 2 {
                        demoIcon("bubble.left", dimmed: true)
                        demoIcon("cloud", dimmed: true)
                        if phase == 1 {
                            demoIcon("terminal", highlighted: true)
                                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                        }
                    }
                }
                .padding(.horizontal, phase == 2 ? 0 : 8)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(phase == 2 ? Color.clear : Color.primary.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            phase == 2 ? Color.clear : Color.primary.opacity(0.08),
                            style: StrokeStyle(lineWidth: 0.7, dash: [3, 2.5])
                        )
                )

                // Eave dot divider
                if phase != 2 {
                    Circle()
                        .fill(Color.primary.opacity(0.62))
                        .frame(width: 4.5, height: 4.5)
                        .padding(.horizontal, 9)
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                }

                // Visible section
                HStack(spacing: 8) {
                    if phase == 0 {
                        demoIcon("terminal", highlighted: true)
                            .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
                    }
                    demoIcon("network", dimmed: false)
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.primary.opacity(0.09))
                        )
                    demoIcon("wifi", dimmed: true)
                    demoIcon("battery.100percent", dimmed: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                    .fill(EavePalette.cardFill(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                    .strokeBorder(EavePalette.cardBorder(colorScheme), lineWidth: 0.65)
            )
            .animation(EaveMotion.notchMorph, value: phase)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(EavePalette.insetFill(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(EavePalette.insetBorder(colorScheme), lineWidth: 0.6)
        )
        .onAppear {
            startAnimationLoop()
        }
        .onDisappear {
            loopTask?.cancel()
            loopTask = nil
        }
        .onChange(of: reduceMotion) { _, _ in
            startAnimationLoop()
        }
    }

    private var phaseCaption: String {
        switch phase {
        case 0: "1. Hold ⌘ and grab any icon on the right"
        case 1: "2. Drag it left of the • dot divider"
        default: "3. Click Eave — everything left of • hides cleanly"
        }
    }

    private func demoIcon(_ symbol: String, dimmed: Bool = false, highlighted: Bool = false) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: highlighted ? .semibold : .medium))
            .foregroundStyle(
                highlighted
                    ? Color.primary
                    : Color.primary.opacity(dimmed ? 0.50 : 0.78)
            )
            .frame(width: 20, height: 20)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(highlighted ? Color.primary.opacity(0.11) : Color.clear)
            )
    }

    private func startAnimationLoop() {
        loopTask?.cancel()
        loopTask = nil
        // Reduce Motion: hold a single static frame instead of looping the drag demo.
        guard !reduceMotion else {
            phase = 0
            return
        }
        loopTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_900_000_000)
                guard !Task.isCancelled else { break }
                phase = 1
                try? await Task.sleep(nanoseconds: 1_900_000_000)
                guard !Task.isCancelled else { break }
                phase = 2
                try? await Task.sleep(nanoseconds: 2_300_000_000)
                guard !Task.isCancelled else { break }
                phase = 0
            }
        }
    }
}
