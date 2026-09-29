import Foundation

extension WorkspaceSession {
    func readImageData(path: String, maxBytes: Int = 20 * 1024 * 1024) async throws -> Data {
        guard maxBytes >= 0 else { throw WorkspaceFileStore.ImageReadFailure.invalidSizeLimit }
        if let folder {
            do {
                let bytes = try await folder.readImageData(path: path, maxBytes: maxBytes)
                let blob = try storeBlob(bytes)
                var next = manifest
                next.attachments[path] = SyncCachedAttachment(blob: blob, revision: nil, remoteID: nil)
                try commit(next)
                return bytes
            } catch {
                if Self.isUnavailable(error), let cached = manifest.attachments[path] {
                    return try boundedAttachment(cached.blob, maxBytes: maxBytes)
                }
                throw error
            }
        }
        guard let remote else { throw StorageError.rootUnavailable }
        let relative = try Self.attachmentPath(path)
        guard let file = manifest.entries[relative]?.file else { throw StorageError.http(404) }
        guard !file.isDirectory else { throw WorkspaceFileStore.ImageReadFailure.notRegularFile }
        if let size = file.size, size > Int64(maxBytes) { throw StorageError.tooLarge }
        if let cached = manifest.attachments[relative], cached.remoteID == file.id,
           file.revision != nil, cached.revision == file.revision {
            return try boundedAttachment(cached.blob, maxBytes: maxBytes)
        }
        do {
            let result = try await remote.download(file, maxBytes: maxBytes)
            guard result.file.id == file.id, result.file.path == file.path, !result.file.isDirectory else {
                throw StorageError.invalidResponse
            }
            guard result.data.count <= maxBytes else { throw StorageError.tooLarge }
            let blob = try storeBlob(result.data)
            var next = manifest
            next.attachments[relative] = SyncCachedAttachment(blob: blob, revision: result.file.revision,
                                                             remoteID: result.file.id)
            try commit(next)
            return result.data
        } catch {
            if Self.isUnavailable(error), let cached = manifest.attachments[relative], cached.remoteID == file.id {
                return try boundedAttachment(cached.blob, maxBytes: maxBytes)
            }
            throw error
        }
    }

    func boundedAttachment(_ blob: String, maxBytes: Int) throws -> Data {
        let bytes = try data(blob)
        guard bytes.count <= maxBytes else { throw StorageError.tooLarge }
        return bytes
    }

    static func attachmentPath(_ path: String) throws -> String {
        guard !path.hasPrefix("/"), !path.hasPrefix("~"), !path.contains("\\"), !path.contains("\0") else {
            throw StorageError.unsafePath(path)
        }
        var normalized: [String] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: false) {
            if part == "." { continue }
            if part == ".." {
                guard !normalized.isEmpty else { throw StorageError.unsafePath(path) }
                normalized.removeLast()
            } else {
                guard !part.isEmpty else { throw StorageError.unsafePath(path) }
                normalized.append(String(part))
            }
        }
        let relative = normalized.joined(separator: "/")
        try StorageError.validate(path: relative)
        return relative
    }
}
