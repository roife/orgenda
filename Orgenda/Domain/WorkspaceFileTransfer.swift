import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let orgendaWorkspaceFile = UTType(exportedAs: "com.roifewu.orgenda.workspace-file")
}

struct WorkspaceFileTransfer: Codable, Transferable, Identifiable {
    var id: String { document.path }
    let workspaceID: UUID
    let document: WorkspaceDocument
    let snapshot: [WorkspaceDocument]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .orgendaWorkspaceFile)
    }

    static func contains(_ path: String, in parent: String) -> Bool {
        path == parent || path.hasPrefix(parent + "/")
    }

    static func matches(_ lhs: [WorkspaceDocument], _ rhs: [WorkspaceDocument]) -> Bool {
        let a = lhs.sorted { $0.path < $1.path }, b = rhs.sorted { $0.path < $1.path }
        return a.count == b.count && zip(a, b).allSatisfy {
            $0.path == $1.path && $0.kind == $1.kind && $0.contents.utf8.elementsEqual($1.contents.utf8)
        }
    }
}

struct WorkspaceTrashEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let originalPath: String
    let title: String
    let kind: WorkspaceDocument.Kind
    let deletedAt: Date

    var storageFolder: String { ".orgenda-trash/" + id.uuidString }
    var storagePath: String { storageFolder + "/item" }
}

enum WorkspaceFileUndo {
    case move(WorkspaceFileTransfer, originalFolder: String)
    case delete(WorkspaceTrashEntry)

    var message: String {
        switch self {
        case .move(let file, _): String(localized: "Moved \(file.document.title)")
        case .delete(let entry): String(localized: "Deleted \(entry.title)")
        }
    }
}

enum WorkspaceFileActionError: LocalizedError {
    case changed, invalidDestination, nameExists, busy

    var errorDescription: String? {
        switch self {
        case .changed: String(localized: "The file or folder changed. Refresh it and try again.")
        case .invalidDestination: String(localized: "Choose another folder. A folder cannot be moved into itself or its children.")
        case .nameExists: String(localized: "An item with this name already exists in the destination. Nothing was replaced.")
        case .busy: String(localized: "Finish saving or resolve the file conflict before moving or deleting items.")
        }
    }
}
