import Foundation
import Network

struct SyncEngineStatus: Sendable {
    var isSynchronizing = false
    var error: String?
    var storageError: StorageError?
    var retryAt: Date?
}

/// The only owner of sync scheduling. Requests arriving during a pass join the
/// same task. Edits and source-change events retain a follow-up pass.
actor SyncEngine {
    private let store: LocalStore
    private var running: Task<Void, Error>?
    private var requested: LocalStore.SyncMode?
    private var requestedPaths: Set<String>?
    private var isFullScan = false
    private var lastFullSync: Date?
    private var retryTask: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?
    private var retryAt: Date?
    private var serverRetryAt: Date?
    private var failures = 0
    private var status = SyncEngineStatus()
    private var listeners: [UUID: AsyncStream<SyncEngineStatus>.Continuation] = [:]
    private var foreground = false
    private let network = NWPathMonitor()
    private var networkWasAvailable = true
    private var started = false
    private var stopped = false

    init(store: LocalStore) { self.store = store }

    deinit {
        network.cancel()
        retryTask?.cancel()
        periodicTask?.cancel()
        running?.cancel()
    }

    func updates() -> AsyncStream<SyncEngineStatus> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            listeners[id] = continuation
            continuation.yield(status)
            continuation.onTermination = { [weak self] _ in Task { await self?.removeListener(id) } }
        }
    }

    private func removeListener(_ id: UUID) { listeners.removeValue(forKey: id) }
    private func publish() { for listener in listeners.values { listener.yield(status) } }

    func start() {
        guard !started else { return }
        started = true
        network.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { await self?.networkChanged(available) }
        }
        network.start(queue: DispatchQueue(label: "orgenda.sync.network"))
    }

    func stop() async {
        stopped = true
        network.cancel()
        retryTask?.cancel()
        periodicTask?.cancel()
        running?.cancel()
        try? await running?.value
        for listener in listeners.values { listener.finish() }
        listeners.removeAll()
    }

    private func networkChanged(_ available: Bool) async {
        let recovered = available && !networkWasAvailable
        networkWasAvailable = available
        if recovered, foreground {
            retryAt = nil
            try? await request(.full, automatic: true)
        }
    }

    func setForeground(_ active: Bool) async {
        start()
        foreground = active
        periodicTask?.cancel()
        guard active else { return }
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = await self?.store.minimumSyncInterval else { return }
                do { try await Task.sleep(for: .seconds(interval)) } catch { return }
                try? await self?.poll()
            }
        }
        try? await poll()
    }

    /// Foreground/timer refreshes can join an existing pass. Actual source
    /// notifications and pending edits must still schedule follow-up work.
    func poll() async throws {
        if isFullScan, let running { try await running.value; return }
        let interval = await store.minimumSyncInterval
        if let lastFullSync, Date.now.timeIntervalSince(lastFullSync) < interval { return }
        try await request(.full, automatic: true)
    }

    func waitUntilIdle() async throws { try await running?.value }

    func cancelCurrent() { running?.cancel() }

    func resolveConflict(path: String, resolution: WorkspaceConflictResolution) async throws {
        if let serverRetryAt, serverRetryAt > .now { throw StorageError.throttled(serverRetryAt.timeIntervalSinceNow) }
        while let active = running { try? await active.value }
        let task = Task { try await self.performResolution(path: path, resolution: resolution) }
        running = task
        try await task.value
    }

    private func performResolution(path: String, resolution: WorkspaceConflictResolution) async throws {
        status.isSynchronizing = true
        publish()
        do {
            try await store.resolveConflict(path: path, resolution: resolution)
            try await drain()
        } catch {
            running = nil
            status.isSynchronizing = false
            status.error = error.localizedDescription
            status.storageError = error as? StorageError
            publish()
            throw error
        }
    }

    func sourceChanged(paths: Set<String>?) async throws {
        try await request(.full, automatic: true, paths: paths, requiresFollowUp: true)
    }

    func request(_ mode: LocalStore.SyncMode, automatic: Bool = false, paths: Set<String>? = nil,
                 requiresFollowUp: Bool = false) async throws {
        if let active = running, active.isCancelled { try? await active.value }
        try await schedule(mode, automatic: automatic, paths: paths, requiresFollowUp: requiresFollowUp).value
    }

    func schedule(_ mode: LocalStore.SyncMode, automatic: Bool = false, paths: Set<String>? = nil,
                  requiresFollowUp: Bool = false) -> Task<Void, Error> {
        guard !stopped else { return Task { throw CancellationError() } }
        if let serverRetryAt, serverRetryAt > .now { return Task {} }
        if automatic, let retryAt, retryAt > .now { return Task {} }
        if !requiresFollowUp, mode == .full, isFullScan, let running { return running }
        if requested == nil {
            requested = mode
            requestedPaths = paths
        } else if mode == .full {
            if requested == .full, let existing = requestedPaths, let paths { requestedPaths = existing.union(paths) }
            else { requestedPaths = nil }
            requested = .full
        }
        if let running { return running }
        let task = Task { try await self.drain() }
        running = task
        return task
    }

    private func drain() async throws {
        status.isSynchronizing = true
        status.error = nil
        status.storageError = nil
        publish()
        defer { running = nil; isFullScan = false; status.isSynchronizing = false; publish() }
        do {
            while let mode = requested {
                let paths = requestedPaths
                requested = nil
                requestedPaths = nil
                isFullScan = mode == .full && paths == nil
                try Task.checkCancellation()
                try await store.synchronize(mode: mode, paths: paths)
                if isFullScan { lastFullSync = .now }
            }
            failures = 0
            retryAt = nil
            serverRetryAt = nil
            status.retryAt = nil
            retryTask?.cancel()
        } catch {
            if error is CancellationError { throw error }
            failures = min(failures + 1, 8)
            let delay: TimeInterval
            if case StorageError.throttled(let requestedDelay) = error {
                delay = max(1, requestedDelay)
                serverRetryAt = .now.addingTimeInterval(delay)
            } else { delay = min(300, pow(2, Double(failures)) * 2) }
            retryAt = .now.addingTimeInterval(delay)
            status.retryAt = retryAt
            status.error = error.localizedDescription
            status.storageError = error as? StorageError
            publish()
            retryTask?.cancel()
            retryTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                try? await self?.request(.full, automatic: true)
            }
            throw error
        }
    }
}
