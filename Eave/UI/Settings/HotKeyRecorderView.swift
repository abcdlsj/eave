import AppKit
import SwiftUI

/// Native SwiftUI keyboard shortcut recorder backed by a temporary local NSEvent monitor.
struct HotKeyRecorderView: View {
    let combo: KeyCombo?
    let onChange: (KeyCombo?) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                Text(labelText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .frame(minWidth: 112)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isRecording ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isRecording ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            if combo != nil {
                Button {
                    stopRecording()
                    onChange(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear Shortcut")
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private var labelText: String {
        if isRecording { return "Type Shortcut..." }
        return combo?.displayString ?? "Record"
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape cancels recording.
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
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
