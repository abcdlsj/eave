import AppKit
import Carbon
import Foundation

/// Logical sections of the macOS menu bar managed by Eave.
enum MenuBarSection: String, CaseIterable, Sendable, Codable {
    case visible
    case hidden
    case alwaysHidden

    var displayName: String {
        switch self {
        case .visible: "Visible"
        case .hidden: "Hidden"
        case .alwaysHidden: "Always Hidden"
        }
    }
}

/// Snapshot metadata describing a third-party or system menu bar status item.
struct MenuBarItemInfo: Identifiable, Sendable, Equatable, Hashable {
    let id: String
    let windowID: CGWindowID
    let pid: pid_t
    let bundleIdentifier: String?
    let appName: String
    let title: String
    let frame: CGRect
    let section: MenuBarSection

    var searchableText: String {
        if title.isEmpty || title.caseInsensitiveCompare(appName) == .orderedSame {
            return appName
        }
        return "\(appName) \(title)"
    }
}

/// Display model combining discovered item metadata with an optional captured icon image.
struct CapturedMenuBarItem: Identifiable {
    let info: MenuBarItemInfo
    let image: NSImage?
    let isLiveCapture: Bool

    var id: String { info.id }
}

/// Global macOS menu bar spacing preference values.
struct MenuBarSpacingConfig: Equatable, Sendable {
    /// Value for `NSStatusItemSpacing` (`nil` means system default).
    var spacing: Int?
    /// Value for `NSStatusItemSelectionPadding` (`nil` means system default).
    var selectionPadding: Int?

    static let systemDefault = MenuBarSpacingConfig(spacing: nil, selectionPadding: nil)
}

/// Global keyboard actions supported by Eave.
enum HotKeyAction: String, CaseIterable, Identifiable, Sendable {
    case toggleHidden
    case toggleNotchBar
    case openSearch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleHidden: "Toggle Hidden Section"
        case .toggleNotchBar: "Toggle Notch Bar"
        case .openSearch: "Search Menu Bar Items"
        }
    }

    var defaultCombo: KeyCombo {
        switch self {
        case .toggleHidden:
            // Option + Command + H
            KeyCombo(keyCode: UInt32(kVK_ANSI_H), carbonModifiers: UInt32(optionKey | cmdKey))
        case .toggleNotchBar:
            // Option + Command + N
            KeyCombo(keyCode: UInt32(kVK_ANSI_N), carbonModifiers: UInt32(optionKey | cmdKey))
        case .openSearch:
            // Option + Command + K
            KeyCombo(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(optionKey | cmdKey))
        }
    }
}

/// Portable representation of a global keyboard shortcut using Carbon virtual key codes.
struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        self.keyCode = UInt32(keyCode)
        self.carbonModifiers = Self.carbonFlags(from: modifierFlags)
    }

    static func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    var displayString: String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.keyLabel(for: keyCode))
        return parts.joined()
    }

    static func keyLabel(for keyCode: UInt32) -> String {
        let map: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
            kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Escape: "⎋",
            kVK_Tab: "⇥", kVK_Delete: "⌫",
            kVK_ANSI_Slash: "/", kVK_ANSI_Period: ".", kVK_ANSI_Comma: ",",
            kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=",
            kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
        ]
        return map[Int(keyCode)] ?? "#\(keyCode)"
    }
}
