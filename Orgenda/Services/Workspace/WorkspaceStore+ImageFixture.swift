#if DEBUG
import Foundation
import UIKit

extension WorkspaceStore {
    /// An isolated on-disk fixture is necessary to exercise coordinated image
    /// reads; the regular text-only preview workspace has no filesystem store.
    func configureImagePreviewFixture() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OrgendaImagePreviewUITest", isDirectory: true)
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
        for path in ["notes/images", ".attach/ab/cd-image-preview"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 100)).image { context in
            UIColor(red: 0.18, green: 0.43, blue: 0.53, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 100))
            UIColor(red: 0.69, green: 0.84, blue: 0.87, alpha: 1).setFill()
            context.fill(CGRect(x: 16, y: 16, width: 68, height: 68))
            ("Image preview" as NSString).draw(at: CGPoint(x: 104, y: 37), withAttributes: [
                .font: UIFont.systemFont(ofSize: 21, weight: .semibold), .foregroundColor: UIColor.white
            ])
        }
        let data = image.pngData()!
        try data.write(to: root.appendingPathComponent("notes/images/picture.png"))
        try data.write(to: root.appendingPathComponent(".attach/ab/cd-image-preview/picture.png"))
        let source = """
        #+title: Image preview
        * Relative file
        [[file:images/picture.png][Relative picture]]

        * Shared attachment
        :PROPERTIES:
        :ID: abcd-image-preview
        :END:
        [[attachment:picture.png][Attached picture]]

        * Missing image
        [[file:images/missing.png][Missing picture]]

        * [[file:images/picture.png][Heading picture]]
        """ + "\n"
        try source.write(to: root.appendingPathComponent("notes/note.org"), atomically: true, encoding: .utf8)
        let disk = WorkspaceFileStore(rootURL: root)
        documents = try await disk.load()
        items = []
        journalEntries = []
        fileStore = disk
        persistedContents = Dictionary(uniqueKeysWithValues: documents.filter { $0.kind != .folder }.map { ($0.path, $0.contents) })
        isFolderConnected = true
        usesEmacsConfiguration = false
        workspaceFileSessionID = UUID()
        scheduleWorkspaceParse()
        await waitForWorkspaceIndex()
    }
}
#endif
