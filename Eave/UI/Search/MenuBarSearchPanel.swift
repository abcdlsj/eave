import AppKit
import Observation
import SwiftUI

/// Key-capable floating search panel (Raycast / Spotlight monochrome studio style)
/// for instant keyboard access to any menu bar item.
final class MenuBarSearchWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
    }
}

enum SearchSectionFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case hidden = "Hidden"
    case visible = "Visible"

    var id: String { rawValue }

    var next: SearchSectionFilter {
        switch self {
        case .all: .hidden
        case .hidden: .visible
        case .visible: .all
        }
    }

    func matches(_ section: MenuBarSection) -> Bool {
        switch self {
        case .all: true
        case .hidden: section != .visible
        case .visible: section == .visible
        }
    }
}

@MainActor
@Observable
final class MenuBarSearchController: NSObject, NSWindowDelegate {
    private var panel: MenuBarSearchWindow?
    private var keyMonitor: Any?
    private var closeTask: Task<Void, Never>?

    private(set) var appearanceMode: AppAppearanceMode = .system
    var query: String = "" {
        didSet { selectedIndex = 0 }
    }
    var sectionFilter: SearchSectionFilter = .all {
        didSet { selectedIndex = 0 }
    }
    var allItems: [MenuBarItemInfo] = []
    var selectedIndex: Int = 0
    private(set) var isVisible: Bool = false
    private(set) var isPresented: Bool = false
    private(set) var isRefreshing: Bool = false

    var onSelectItem: ((MenuBarItemInfo) -> Void)?
    var onRequestRefreshItems: (() async -> [MenuBarItemInfo])?

    var filteredItems: [MenuBarItemInfo] {
        let scoped = allItems.filter { sectionFilter.matches($0.section) }
        return MenuBarSearchEngine.filter(items: scoped, query: query)
    }

    func count(for filter: SearchSectionFilter) -> Int {
        allItems.reduce(into: 0) { count, item in
            if filter.matches(item.section) { count += 1 }
        }
    }

    func applyAppearance(_ mode: AppAppearanceMode) {
        appearanceMode = mode
        panel?.appearance = mode.nsAppearance
    }

    func toggle() {
        if isVisible {
            close()
        } else {
            open()
        }
    }

    func open(initialItems: [MenuBarItemInfo] = []) {
        closeTask?.cancel()
        closeTask = nil

        if !initialItems.isEmpty {
            allItems = initialItems
        }
        query = ""
        sectionFilter = .all
        selectedIndex = 0
        isVisible = true
        isPresented = false

        if panel == nil {
            let rect = NSRect(x: 0, y: 0, width: 556, height: 416)
            let window = MenuBarSearchWindow(contentRect: rect)
            window.appearance = appearanceMode.nsAppearance
            window.delegate = self
            let view = MenuBarSearchView(controller: self)
            window.contentView = NSHostingView(rootView: view)
            panel = window
        }

        if let panel, let screen = NotchGeometryResolver.preferredScreen() ?? NSScreen.main {
            let x = screen.frame.midX - panel.frame.width / 2
            let y = screen.frame.maxY - panel.frame.height - 135
            panel.setFrameOrigin(NSPoint(x: x, y: y))
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        installKeyMonitor()
        EaveHaptics.tick()

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible else { return }
            withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                self.isPresented = true
            }
        }

        isRefreshing = true
        Task {
            defer { isRefreshing = false }
            if let items = await onRequestRefreshItems?() {
                allItems = items
            }
        }
    }

    func close() {
        guard isVisible else { return }
        isVisible = false
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }

        withAnimation(.easeOut(duration: 0.12)) {
            isPresented = false
        }

        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 130_000_000)
            guard !Task.isCancelled, let self, !self.isVisible else { return }
            self.panel?.orderOut(nil)
        }
    }

    func selectCurrent() {
        let items = filteredItems
        guard items.indices.contains(selectedIndex) else { return }
        let chosen = items[selectedIndex]
        EaveHaptics.tick()
        close()
        onSelectItem?(chosen)
    }

    func select(_ info: MenuBarItemInfo) {
        EaveHaptics.tick()
        close()
        onSelectItem?(info)
    }

    func windowDidResignKey(_ notification: Notification) {
        if isVisible {
            close()
        }
    }

    private func installKeyMonitor() {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            switch event.keyCode {
            case 53: // Escape
                self.close()
                return nil
            case 48: // Tab cycles section filter
                EaveHaptics.tick()
                withAnimation(EaveMotion.microSpring) {
                    self.sectionFilter = self.sectionFilter.next
                }
                return nil
            case 125: // Down arrow
                let count = self.filteredItems.count
                if count > 0 {
                    withAnimation(EaveMotion.microSpring) {
                        self.selectedIndex = (self.selectedIndex + 1) % count
                    }
                }
                return nil
            case 126: // Up arrow
                let count = self.filteredItems.count
                if count > 0 {
                    withAnimation(EaveMotion.microSpring) {
                        self.selectedIndex = (self.selectedIndex - 1 + count) % count
                    }
                }
                return nil
            case 36: // Return
                self.selectCurrent()
                return nil
            default:
                return event
            }
        }
    }
}

struct MenuBarSearchView: View {
    @Bindable var controller: MenuBarSearchController
    @FocusState private var isFieldFocused: Bool
    @Namespace private var filterNamespace
    @Namespace private var selectionNamespace

    var body: some View {
        VStack(spacing: 0) {
            // Search input header
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(controller.query.isEmpty ? .secondary : .primary)

                TextField("Search menu bar items…", text: $controller.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .regular))
                    .focused($isFieldFocused)
                    .onSubmit {
                        controller.selectCurrent()
                    }

                if controller.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.70)
                        .transition(.opacity)
                }

                if !controller.query.isEmpty {
                    Button {
                        EaveHaptics.tick()
                        withAnimation(EaveMotion.hover) {
                            controller.query = ""
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary.opacity(0.75))
                    }
                    .buttonStyle(EaveTactileButtonStyle(pressedScale: 0.86))
                    .accessibilityLabel("Clear search")
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Understated monochrome section filter pills
            HStack(spacing: 5) {
                ForEach(SearchSectionFilter.allCases) { filter in
                    filterPill(filter)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Rectangle()
                .fill(Color.primary.opacity(0.075))
                .frame(height: 0.6)

            // Results list
            let items = controller.filteredItems
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: controller.query.isEmpty ? "rectangle.topthird.inset.filled" : "magnifyingglass")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.tertiary)
                    Text(controller.query.isEmpty ? "No menu bar items discovered" : "No matches for \"\(controller.query)\"")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Grant Accessibility permission in Settings for complete discovery.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 36)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                SearchItemRow(
                                    item: item,
                                    query: controller.query,
                                    isSelected: index == controller.selectedIndex,
                                    selectionNamespace: selectionNamespace,
                                    onHoverSelect: {
                                        if controller.selectedIndex != index {
                                            withAnimation(EaveMotion.microSpring) {
                                                controller.selectedIndex = index
                                            }
                                        }
                                    },
                                    onTap: {
                                        controller.select(item)
                                    }
                                )
                                .id(index)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                    }
                    .onChange(of: controller.selectedIndex) { _, newValue in
                        withAnimation(.easeOut(duration: 0.13)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }

            Rectangle()
                .fill(Color.primary.opacity(0.075))
                .frame(height: 0.6)

            // Minimalist keycap footer
            HStack(spacing: 12) {
                keyHint("↑↓", label: "Navigate")
                keyHint("⇥", label: "Filter")
                keyHint("↩", label: "Open")
                keyHint("⎋", label: "Close")
                Spacer()
                Text(items.count == 1 ? "1 item" : "\(items.count) items")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
        .frame(width: 536, height: 396)
        .eaveGlassSurface(cornerRadius: 18)
        .preferredColorScheme(controller.appearanceMode.colorScheme)
        .scaleEffect(controller.isPresented ? 1.0 : 0.965)
        .offset(y: controller.isPresented ? 0 : -6)
        .opacity(controller.isPresented ? 1.0 : 0.0)
        .frame(width: 556, height: 416)
        .onAppear {
            isFieldFocused = true
        }
        .onChange(of: controller.isVisible) { _, visible in
            if visible { isFieldFocused = true }
        }
    }

    private func filterPill(_ filter: SearchSectionFilter) -> some View {
        let isActive = controller.sectionFilter == filter
        let count = controller.count(for: filter)

        return Button {
            EaveHaptics.tick()
            withAnimation(EaveMotion.microSpring) {
                controller.sectionFilter = filter
            }
        } label: {
            HStack(spacing: 4.5) {
                Text(filter.rawValue)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                Text("\(count)")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary.opacity(isActive ? 0.9 : 0.6))
            }
            .foregroundStyle(isActive ? .primary : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background {
                if isActive {
                    Capsule()
                        .fill(Color.primary.opacity(0.095))
                        .matchedGeometryEffect(id: "activeFilterPill", in: filterNamespace)
                }
            }
        }
        .buttonStyle(EaveTactileButtonStyle(pressedScale: 0.95))
    }

    private func keyHint(_ key: String, label: String) -> some View {
        HStack(spacing: 4.5) {
            EaveKeycap(label: key, fontSize: 9.5, horizontalPadding: 4.5, verticalPadding: 1.5)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
    }
}

private struct SearchItemRow: View {
    let item: MenuBarItemInfo
    let query: String
    let isSelected: Bool
    let selectionNamespace: Namespace.ID
    let onHoverSelect: () -> Void
    let onTap: () -> Void

    private var resolved: AppIconService.ResolvedIcon {
        AppIconService.shared.resolve(for: item)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                rowIcon
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1.5) {
                    highlightedText(item.appName, query: query)
                        .lineLimit(1)

                    if !item.title.isEmpty && item.title != item.appName {
                        Text(item.title)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(item.section.displayName)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(item.section == .visible ? .tertiary : .secondary)
                    .padding(.horizontal, 7.5)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule()
                            .fill(item.section == .visible ? Color.clear : Color.primary.opacity(0.06))
                    )

                if isSelected {
                    EaveKeycap(label: "↩", fontSize: 9.5, horizontalPadding: 4.5, verticalPadding: 1.5)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.085))
                        .matchedGeometryEffect(id: "searchRowSelection", in: selectionNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(EaveTactileButtonStyle(pressedScale: 0.99, pressedOpacity: 0.90))
        .onHover { hovering in
            if hovering {
                onHoverSelect()
            }
        }
    }

    private func highlightedText(_ text: String, query: String) -> Text {
        let indices = MenuBarSearchEngine.matchedIndices(in: text, query: query)
        guard !indices.isEmpty else {
            return Text(text)
                .font(.system(size: 13.5, weight: isSelected ? .medium : .regular))
                .foregroundStyle(.primary)
        }
        var attributed = AttributedString()
        for (idx, ch) in text.enumerated() {
            var segment = AttributedString(String(ch))
            if indices.contains(idx) {
                segment.foregroundColor = .primary
                segment.font = .system(size: 13.5, weight: .semibold)
            } else {
                segment.foregroundColor = .secondary
                segment.font = .system(size: 13.5, weight: .regular)
            }
            attributed.append(segment)
        }
        return Text(attributed)
    }

    @ViewBuilder
    private var rowIcon: some View {
        if let appIcon = resolved.image {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.065))
                Image(systemName: resolved.symbolName ?? "menubar.rectangle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.8))
            }
        }
    }
}
