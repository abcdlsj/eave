import AppKit
import Observation
import SwiftUI

/// Key-capable floating search panel (Raycast / Spotlight style) for instant keyboard access to any menu bar item.
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

@MainActor
@Observable
final class MenuBarSearchController {
    private var panel: MenuBarSearchWindow?
    private var keyMonitor: Any?

    var query: String = "" {
        didSet { selectedIndex = 0 }
    }
    var allItems: [CapturedMenuBarItem] = []
    var selectedIndex: Int = 0
    private(set) var isVisible: Bool = false

    var onSelectItem: ((MenuBarItemInfo) -> Void)?
    var onRequestRefreshItems: (() async -> [CapturedMenuBarItem])?

    var filteredItems: [CapturedMenuBarItem] {
        let infoMap = Dictionary(uniqueKeysWithValues: allItems.map { ($0.info.id, $0) })
        let rankedInfos = MenuBarSearchEngine.filter(items: allItems.map(\.info), query: query)
        return rankedInfos.compactMap { infoMap[$0.id] }
    }

    func toggle() {
        if isVisible {
            close()
        } else {
            open()
        }
    }

    func open() {
        query = ""
        selectedIndex = 0
        isVisible = true

        if panel == nil {
            let rect = NSRect(x: 0, y: 0, width: 520, height: 380)
            let window = MenuBarSearchWindow(contentRect: rect)
            let view = MenuBarSearchView(controller: self)
            window.contentView = NSHostingView(rootView: view)
            panel = window
        }

        if let panel, let screen = NotchGeometryResolver.preferredScreen() ?? NSScreen.main {
            let x = screen.frame.midX - panel.frame.width / 2
            let y = screen.frame.maxY - panel.frame.height - 150
            panel.setFrameOrigin(NSPoint(x: x, y: y))
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        installKeyMonitor()

        Task {
            if let items = await onRequestRefreshItems?() {
                allItems = items
            }
        }
    }

    func close() {
        isVisible = false
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        panel?.orderOut(nil)
    }

    func selectCurrent() {
        let items = filteredItems
        guard items.indices.contains(selectedIndex) else { return }
        let chosen = items[selectedIndex].info
        close()
        onSelectItem?(chosen)
    }

    func select(_ info: MenuBarItemInfo) {
        close()
        onSelectItem?(info)
    }

    private func installKeyMonitor() {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            switch event.keyCode {
            case 53: // Escape
                self.close()
                return nil
            case 125: // Down arrow
                let count = self.filteredItems.count
                if count > 0 { self.selectedIndex = (self.selectedIndex + 1) % count }
                return nil
            case 126: // Up arrow
                let count = self.filteredItems.count
                if count > 0 { self.selectedIndex = (self.selectedIndex - 1 + count) % count }
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

    var body: some View {
        VStack(spacing: 0) {
            // Search input header
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search menu bar items...", text: $controller.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16.5, weight: .regular))
                    .focused($isFieldFocused)
                    .onSubmit {
                        controller.selectCurrent()
                    }

                if !controller.query.isEmpty {
                    Button {
                        controller.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)

            Divider()
                .opacity(0.6)

            // Results list
            let items = controller.filteredItems
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No matching menu bar items")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Grant Accessibility permission in Settings for complete item discovery.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                SearchItemRow(
                                    item: item,
                                    isSelected: index == controller.selectedIndex
                                )
                                .id(index)
                                .onTapGesture {
                                    controller.select(item.info)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: controller.selectedIndex) { _, newValue in
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }

            Divider()
                .opacity(0.6)

            // Footer with tactile keycaps
            HStack(spacing: 12) {
                keyHint("↑↓", label: "Navigate")
                keyHint("↩", label: "Open")
                keyHint("⎋", label: "Close")
                Spacer()
                Text("\(items.count) items")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
        .frame(width: 520, height: 380)
        .eaveGlassSurface(cornerRadius: 20)
        .onAppear {
            isFieldFocused = true
        }
    }

    private func keyHint(_ key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
    }
}

private struct SearchItemRow: View {
    let item: CapturedMenuBarItem
    let isSelected: Bool

    private var resolved: AppIconService.ResolvedIcon {
        AppIconService.shared.resolve(for: item.info)
    }

    var body: some View {
        HStack(spacing: 12) {
            rowIcon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1.5) {
                Text(item.info.appName)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !item.info.title.isEmpty && item.info.title != item.info.appName {
                    Text(item.info.title)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(item.info.section.displayName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(item.info.section == .visible ? .secondary : resolved.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(
                            item.info.section == .visible
                                ? Color.primary.opacity(0.06)
                                : resolved.accentColor.opacity(0.14)
                        )
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor.opacity(0.32) : Color.clear, lineWidth: 0.75)
                )
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var rowIcon: some View {
        if let appIcon = resolved.image {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(resolved.accentColor.opacity(0.16))
                Image(systemName: resolved.symbolName ?? "menubar.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(resolved.accentColor)
            }
        }
    }
}
