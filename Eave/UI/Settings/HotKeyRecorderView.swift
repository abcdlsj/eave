import AppKit
import Carbon
import SwiftUI

/// Refined monochrome macOS keyboard shortcut recorder with crisp sculpted physical keycaps.
struct HotKeyRecorderView: View {
    @Environment(\.eaveHairline) private var hairline
    let combo: KeyCombo?
    let onChange: (KeyCombo?) -> Void

    @State private var isRecording = false
    @State private var isHovered = false
    @State private var pulseDot = false
    @State private var monitor: Any?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 7) {
            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                HStack(spacing: 4) {
                    if isRecording {
                        Circle()
                            .fill(Color.primary)
                            .frame(width: 5, height: 5)
                            .opacity(pulseDot ? 0.95 : 0.30)

                        Text("Press keys…")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.primary)
                    } else if let combo {
                        ForEach(Array(keyTokens(for: combo).enumerated()), id: \.offset) { _, token in
                            EaveKeycap(
                                label: token,
                                fontSize: 11,
                                horizontalPadding: 5.5,
                                verticalPadding: 2.5
                            )
                        }
                    } else {
                        Text("Record")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 118, minHeight: 28)
                .padding(.horizontal, 9)
                .background(
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .fill(
                            isRecording
                                ? Color.primary.opacity(0.085)
                                : Color.primary.opacity(isHovered ? 0.06 : 0.03)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .strokeBorder(
                            isRecording
                                ? Color.primary.opacity(0.45)
                                : Color.primary.opacity(isHovered ? 0.16 : 0.09),
                            lineWidth: isRecording ? 1.0 : hairline
                        )
                )
            }
            .buttonStyle(EaveTactileButtonStyle(pressedScale: 0.97))
            .accessibilityLabel(recorderAccessibilityLabel)
            .accessibilityHint(isRecording ? "Press a key combination, or Escape to cancel." : "Records a new shortcut.")
            .onHover { hovering in
                withAnimation(EaveMotion.hover) {
                    isHovered = hovering
                }
            }

            if combo != nil && !isRecording {
                Button {
                    stopRecording()
                    onChange(nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.primary.opacity(0.05)))
                        .contentShape(Circle())
                }
                .buttonStyle(EaveTactileButtonStyle(pressedScale: 0.88))
                .help("Clear Shortcut")
                .accessibilityLabel("Clear shortcut")
                .transition(.opacity)
            }
        }
        .animation(EaveMotion.microSpring, value: isRecording)
        .onDisappear {
            stopRecording()
        }
    }

    private var recorderAccessibilityLabel: String {
        if isRecording { return "Recording shortcut" }
        guard let combo else { return "Record shortcut" }
        return "Shortcut: " + Self.spokenTokens(for: combo).joined(separator: " ")
    }

    /// VoiceOver-friendly words for a combo, e.g. "Option Command H".
    static func spokenTokens(for combo: KeyCombo) -> [String] {
        var words: [String] = []
        if combo.carbonModifiers & UInt32(controlKey) != 0 { words.append("Control") }
        if combo.carbonModifiers & UInt32(optionKey) != 0 { words.append("Option") }
        if combo.carbonModifiers & UInt32(shiftKey) != 0 { words.append("Shift") }
        if combo.carbonModifiers & UInt32(cmdKey) != 0 { words.append("Command") }
        let key = KeyCombo.keyLabel(for: combo.keyCode)
        let spokenKeys: [String: String] = [
            "↩": "Return", "⎋": "Escape", "⇥": "Tab", "⌫": "Delete",
            "/": "Slash", ".": "Period", ",": "Comma", "-": "Minus", "=": "Equals",
            "[": "Left Bracket", "]": "Right Bracket"
        ]
        words.append(spokenKeys[key] ?? key)
        return words
    }

    private func keyTokens(for combo: KeyCombo) -> [String] {
        var tokens: [String] = []
        if combo.carbonModifiers & UInt32(controlKey) != 0 { tokens.append("⌃") }
        if combo.carbonModifiers & UInt32(optionKey) != 0 { tokens.append("⌥") }
        if combo.carbonModifiers & UInt32(shiftKey) != 0 { tokens.append("⇧") }
        if combo.carbonModifiers & UInt32(cmdKey) != 0 { tokens.append("⌘") }
        tokens.append(KeyCombo.keyLabel(for: combo.keyCode))
        return tokens
    }

    private func startRecording() {
        isRecording = true
        if reduceMotion {
            pulseDot = true
        } else {
            pulseDot = false
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulseDot = true
            }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !modifiers.isEmpty else {
                return nil
            }
            let recorded = KeyCombo(keyCode: event.keyCode, modifierFlags: modifiers)
            stopRecording()
            onChange(recorded)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        pulseDot = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
