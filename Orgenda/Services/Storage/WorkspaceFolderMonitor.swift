import Foundation

/// NSFilePresenter covers coordinated local edits; NSMetadataQuery also
/// observes materialization and changes delivered by iCloud Drive.
@MainActor
final class WorkspaceFolderMonitor {
    private let presenter: WorkspaceFilePresenter
    private var query: NSMetadataQuery?
    private var notifications: [NSObjectProtocol] = []
    private var stopped = false

    init(root: URL, ubiquitous: Bool, changed: @escaping @Sendable (Set<String>?) -> Void) {
        presenter = WorkspaceFilePresenter(root: root, changed: changed)
        NSFileCoordinator.addFilePresenter(presenter)
        if ubiquitous {
            let query = NSMetadataQuery()
            query.searchScopes = [root]
            query.predicate = NSPredicate(format: "%K BEGINSWITH %@", NSMetadataItemPathKey, root.path + "/")
            for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering, NSNotification.Name.NSMetadataQueryDidUpdate] {
                notifications.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { notification in
                    if notification.name == .NSMetadataQueryDidFinishGathering { changed(nil); return }
                    let keys = [NSMetadataQueryUpdateAddedItemsKey, NSMetadataQueryUpdateChangedItemsKey, NSMetadataQueryUpdateRemovedItemsKey]
                    let items = keys.flatMap { notification.userInfo?[$0] as? [NSMetadataItem] ?? [] }
                    let paths = Set(items.compactMap { item -> String? in
                        guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                              url.path.hasPrefix(root.path + "/") else { return nil }
                        return String(url.path.dropFirst(root.path.count + 1))
                    })
                    changed(paths.isEmpty ? nil : paths)
                })
            }
            query.start()
            self.query = query
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        NSFileCoordinator.removeFilePresenter(presenter)
        query?.stop()
        for notification in notifications { NotificationCenter.default.removeObserver(notification) }
        notifications.removeAll()
        query = nil
    }

    deinit {
        if !stopped { NSFileCoordinator.removeFilePresenter(presenter) }
        query?.stop()
        for notification in notifications { NotificationCenter.default.removeObserver(notification) }
    }
}

private final class WorkspaceFilePresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue
    private let changed: @Sendable (Set<String>?) -> Void

    init(root: URL, changed: @escaping @Sendable (Set<String>?) -> Void) {
        presentedItemURL = root
        self.changed = changed
        presentedItemOperationQueue = OperationQueue()
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        super.init()
    }

    func presentedItemDidChange() { changed(nil) }
    func presentedSubitemDidChange(at url: URL) { notify(url) }
    func presentedSubitemDidAppear(at url: URL) { notify(url) }
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { changed(nil) }
    func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        changed(nil)
        completionHandler(nil)
    }

    private func notify(_ url: URL) {
        guard let root = presentedItemURL, url.path.hasPrefix(root.path + "/") else { changed(nil); return }
        changed([String(url.path.dropFirst(root.path.count + 1))])
    }
}
