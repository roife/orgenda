import Foundation

extension LocalStore {
    func readImageData(path requestedPath: String, maxBytes: Int = 20 * 1024 * 1024) async throws -> Data {
        guard maxBytes >= 0 else { throw WorkspaceFileStore.ImageReadFailure.invalidSizeLimit }
        let path = requestedPath.hasPrefix("/") || requestedPath.hasPrefix("~")
            ? requestedPath : underlyingPath(try Self.attachmentPath(requestedPath))
        switch source {
        case .folder(let folder):
            do {
                let bytes = try await folder.readImageData(path: path, maxBytes: maxBytes)
                let blob = try storeBlob(bytes)
                var next = state
                next.attachments[path] = CachedWorkspaceAttachment(blob: blob, revision: nil, remoteID: nil)
                try commit(next)
                return bytes
            } catch {
                if Self.isUnavailable(error), let cached = state.attachments[path] {
                    return try boundedAttachment(cached.blob, maxBytes: maxBytes)
                }
                throw error
            }
        case .remote(let remote):
            return try await readRemoteImageData(path: path, maxBytes: maxBytes, remote: remote)
        }
    }

    private func readRemoteImageData(path: String, maxBytes: Int, remote: any RemoteWorkspaceBackend) async throws -> Data {
        let relative = try Self.attachmentPath(path)
        guard let file = state.entries[relative]?.file else { throw StorageError.http(404) }
        guard !file.isDirectory else { throw WorkspaceFileStore.ImageReadFailure.notRegularFile }
        if let size = file.size, size > Int64(maxBytes) { throw StorageError.tooLarge }
        if let cached = state.attachments[relative], cached.remoteID == file.id,
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
            var next = state
            next.attachments[relative] = CachedWorkspaceAttachment(blob: blob, revision: result.file.revision,
                                                             remoteID: result.file.id)
            try commit(next)
            return result.data
        } catch {
            if Self.isUnavailable(error), let cached = state.attachments[relative], cached.remoteID == file.id {
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
