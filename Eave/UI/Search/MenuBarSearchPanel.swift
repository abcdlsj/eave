import AppKit
import Observation
import SwiftUI

/// Key-capable floating search panel (Spotlight-style) for quick keyboard access to any menu bar item.
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
            let rect = NSRect(x: 0, y: 0, width: 480, height: 340)
            let window = MenuBarSearchWindow(contentRect: rect)
            let view = MenuBarSearchView(controller: self)
            window.contentView = NSHostingView(rootView: view)
            panel = window
        }

        if let panel, let screen = NotchGeometryResolver.preferredScreen() ?? NSScreen.main {
            let x = screen.frame.midX - panel.frame.width / 2
            let y = screen.frame.maxY - panel.frame.height - 140
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
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search menu bar items...", text: $controller.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($isFieldFocused)
                    .onSubmit {
                        controller.selectCurrent()
                    }

                if !controller.query.isEmpty {
                    Button {
                        controller.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            let items = controller.filteredItems
            if items.isEmpty {
                VStack(spacing: 6) {
                    Text("No matching menu bar items")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Make sure Accessibility permission is enabled for full discovery.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                searchRow(item: item, isSelected: index == controller.selectedIndex)
                                    .id(index)
                                    .onTapGesture {
                                        controller.select(item.info)
                                    }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: controller.selectedIndex) { _, newValue in
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }

            Divider()

            HStack {
                Text("↑↓ Navigate   ↩ Trigger   ⎋ Close")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(items.count) items")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .frame(width: 480, height: 340)
        .eaveGlassSurface(cornerRadius: 16)
        .onAppear {
            isFieldFocused = true
        }
    }

    private func searchRow(item: CapturedMenuBarItem, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            if let image = item.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "menubar.rectangle")
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.info.appName)
                    .font(.system(size: 13, weight: .medium))
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
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(.primary.opacity(0.07), in: Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
