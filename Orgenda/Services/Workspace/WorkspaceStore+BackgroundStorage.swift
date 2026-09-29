import UIKit

extension WorkspaceStore {
    func finishStorageBeforeSuspending() async {
        guard isWorkspaceReady else { return }
        let finishing = Task { await synchronizeFiles() }
        let identifier = UIApplication.shared.beginBackgroundTask(withName: "Save workspace") {
            finishing.cancel()
        }
        await withTaskCancellationHandler {
            await finishing.value
        } onCancel: {
            finishing.cancel()
        }
        if identifier != .invalid { UIApplication.shared.endBackgroundTask(identifier) }
    }
}
