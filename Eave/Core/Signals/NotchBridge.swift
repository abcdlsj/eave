import Foundation

/// Local automation bridge allowing external scripts, CLIs, and self-written apps
/// to display peeks or ambient status dots inside Eave's Notch.
///
/// Supported transports:
/// 1. URL Scheme: `eave://notify?title=...&subtitle=...&badge=...&symbol=...&mode=peek|ambient`
///    and `eave://clear?id=...`
/// 2. DistributedNotificationCenter: name `com.abcdlsj.eave.notch.notify`
@MainActor
final class NotchBridge {
    static let distributedNotificationName = Notification.Name("com.abcdlsj.eave.notch.notify")

    private var distributedObserver: Any?
    var onPayloadReceived: ((BridgePayload) -> Void)?

    func start() {
        stop()
        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.distributedNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let payload = BridgePayload.parse(userInfo: userInfo) else {
                return
            }
            Task { @MainActor [weak self] in
                self?.onPayloadReceived?(payload)
            }
        }
    }

    func stop() {
        if let observer = distributedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            distributedObserver = nil
        }
    }

    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        guard let payload = BridgePayload.parse(url: url) else { return false }
        onPayloadReceived?(payload)
        return true
    }
}
