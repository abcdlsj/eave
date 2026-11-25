import Foundation
import Observation

/// Unified deterministic state machine governing Notch presentation:
/// `idle` <-> `ambient` <-> `peek(alert, expanded)` <-> `bar`.
@MainActor
@Observable
final class NotchStateMachine {
    private(set) var state: NotchState = .idle
    private(set) var ambientIndicators: [AmbientIndicator] = []
    private(set) var isHovering: Bool = false

    private var peekDismissTask: Task<Void, Never>?
    private var pendingPeekAfterBar: NotchAlert?

    /// Optional clock/scheduler hook so unit tests can run deterministically without real sleeps.
    var enableAutoDismissTimers: Bool = true

    func presentPeek(_ alert: NotchAlert) {
        if case .bar = state {
            // Do not interrupt the user while browsing the Notch Bar; remember latest alert.
            pendingPeekAfterBar = alert
            return
        }

        peekDismissTask?.cancel()
        state = .peek(alert, expanded: false)
        schedulePeekDismiss(after: alert.duration)
    }

    func setPeekExpanded(_ expanded: Bool) {
        guard case .peek(let alert, _) = state else { return }
        state = .peek(alert, expanded: expanded)
        if expanded {
            peekDismissTask?.cancel()
        } else {
            schedulePeekDismiss(after: min(alert.duration, 2.5))
        }
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

    func openBar() {
        peekDismissTask?.cancel()
        peekDismissTask = nil
        state = .bar
    }

    func closeBar() {
        guard case .bar = state else { return }
        transitionToRestingState()
        if let pending = pendingPeekAfterBar {
            pendingPeekAfterBar = nil
            presentPeek(pending)
        }
    }

    func toggleBar() {
        if case .bar = state {
            closeBar()
        } else {
            openBar()
        }
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
        switch state {
        case .peek(let alert, _):
            if hovering {
                peekDismissTask?.cancel()
                state = .peek(alert, expanded: true)
            } else {
                state = .peek(alert, expanded: false)
                schedulePeekDismiss(after: 1.8)
            }
        default:
            break
        }
    }

    var isBarOpen: Bool {
        if case .bar = state { return true }
        return false
    }

    var isInteractiveState: Bool {
        switch state {
        case .idle: false
        case .ambient, .peek, .bar: true
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
