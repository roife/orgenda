import Foundation
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    static let orgendaTask = UTType(exportedAs: "com.roifewu.orgenda.task")
}

struct OrgTaskTransfer: Codable, Transferable {
    let item: OrgItem
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .orgendaTask)
    }
}
