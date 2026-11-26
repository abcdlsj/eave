import Foundation
import Observation

/// Unified deterministic state machine governing Notch presentation:
/// `idle` <-> `ambient` <-> `peek(alert)`.
@MainActor
@Observable
final class NotchStateMachine {
    private(set) var state: NotchState = .idle
    private(set) var ambientIndicators: [AmbientIndicator] = []
    private(set) var isHovering: Bool = false

    private var peekDismissTask: Task<Void, Never>?

    /// Optional clock/scheduler hook so unit tests can run deterministically without real sleeps.
    var enableAutoDismissTimers: Bool = true

    func presentPeek(_ alert: NotchAlert) {
        peekDismissTask?.cancel()
        state = .peek(alert)
        schedulePeekDismiss(after: alert.duration)
    }

    func dismissPeek() {
        peekDismissTask?.cancel()
        peekDismissTask = nil
        if case .peek = state {
            transitionToRestingState()
        }
    }

    func upsertAmbient(_ indicator: AmbientIndicator) {
        if let index = ambientIndicators.firstIndex(where: { $0.id == indicator.id }) {
            ambientIndicators[index] = indicator
        } else {
            ambientIndicators.append(indicator)
        }

        if case .idle = state {
            state = .ambient(ambientIndicators)
        } else if case .ambient = state {
            state = .ambient(ambientIndicators)
        }
    }

    func removeAmbient(id: String) {
        ambientIndicators.removeAll { $0.id == id }
        if case .ambient = state {
            transitionToRestingState()
        }
    }

    func clearAllAmbient() {
        ambientIndicators.removeAll()
        if case .ambient = state {
            state = .idle
        }
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
        if case .peek = state {
            if hovering {
                // Pause auto-dismiss while the user moves to click the Notch wings.
                peekDismissTask?.cancel()
            } else {
                schedulePeekDismiss(after: 1.2)
            }
        }
    }

    var isInteractiveState: Bool {
        switch state {
        case .idle: false
        case .ambient, .peek: true
        }
    }

    // MARK: - Private

    private func transitionToRestingState() {
        if ambientIndicators.isEmpty {
            state = .idle
        } else {
            state = .ambient(ambientIndicators)
        }
    }

    private func schedulePeekDismiss(after delay: TimeInterval) {
        peekDismissTask?.cancel()
        guard enableAutoDismissTimers else { return }
        peekDismissTask = Task { [weak self] in
            let nanos = UInt64(max(0.2, delay) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            self?.handleAutoDismissTimeout()
        }
    }

    private func handleAutoDismissTimeout() {
        guard !isHovering else { return }
        if case .peek = state {
            transitionToRestingState()
        }
    }
}
