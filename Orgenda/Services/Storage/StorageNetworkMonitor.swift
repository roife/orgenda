import Foundation
import Network
import Observation

/// A restored route triggers a foreground retry; this is not a connectivity
/// prerequisite for saving or a guarantee that a provider can be reached.
@MainActor @Observable
final class StorageNetworkMonitor {
    var recoveryGeneration = 0
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var previousStatus: NWPath.Status?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                if let previousStatus = self.previousStatus, previousStatus != .satisfied, path.status == .satisfied {
                    self.recoveryGeneration &+= 1
                }
                self.previousStatus = path.status
            }
        }
        monitor.start(queue: DispatchQueue(label: "orgenda.storage.network"))
    }

    deinit { monitor.cancel() }
}
