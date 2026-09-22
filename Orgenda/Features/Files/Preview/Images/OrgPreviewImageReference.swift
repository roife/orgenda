import Foundation

/// A display-only image link. Paths are decoded once here, then handed to the
/// workspace store, which remains responsible for access and symlink checks.
struct OrgPreviewImageReference: Hashable, Sendable {
    let target: String
    let label: String
    let startByte: Int

    enum Failure: Error, Equatable, LocalizedError {
        case invalidLink
        case outsideWorkspace
        case missingAttachmentDirectory
        case invalidAttachmentID

        var errorDescription: String? {
            switch self {
            case .invalidLink:
                String(localized: "This image link has an invalid or unsupported path.")
            case .outsideWorkspace:
                String(localized: "This image path leaves the selected workspace folder.")
            case .missingAttachmentDirectory:
                String(localized: "This attachment needs a DIR or ID property on its heading or an ancestor.")
            case .invalidAttachmentID:
                String(localized: "The attachment ID cannot be used as a directory name.")
            }
        }
    }

    private static let extensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp", "avif", "svg"
    ]

    static func from(_ link: ParsedOrgNode) -> Self? {
        guard link.type == "link",
              let target = link.children.first(where: { $0.type == "link_target" })?.text,
              let path = try? imagePath(in: target),
              extensions.contains((path as NSString).pathExtension.lowercased()) else { return nil }
        let description = link.children.first { $0.type == "link_description" }?.text
        return Self(target: target, label: description ?? (path as NSString).lastPathComponent,
                    startByte: link.startByte)
    }

    /// Local candidates are workspace-relative, except explicit absolute links
    /// and absolute DIR properties. No basename search or file reads occur here.
    func candidates(documentPath: String, document: ParsedOrgDocument?) throws -> [String] {
        switch Self.scheme(in: target) {
        case "http", "https":
            return [try Self.networkURL(target).absoluteString]
        case "attachment":
            let name = try Self.decode(String(target.dropFirst("attachment:".count)))
            guard !name.isEmpty, !name.hasPrefix("/"), !name.hasPrefix("~"),
                  Self.scheme(in: name) == nil else { throw Failure.invalidLink }
            let scopes = document.map { attachmentScopes(in: $0) } ?? []
            if let directory = scopes.reversed().compactMap({ $0["DIR"] }).first {
                // A DIR property is an actual filesystem path, not a link URL;
                // preserve literal percent signs unless it explicitly uses file:.
                let path = Self.scheme(in: directory) == "file"
                    ? try Self.localPath(directory) : directory
                guard Self.scheme(in: path) == nil else { throw Failure.invalidLink }
                let base = try Self.resolve(path, relativeTo: Self.parent(of: documentPath))
                return [try Self.resolve(name, relativeTo: base)]
            }
            guard let id = scopes.reversed().compactMap({ $0["ID"] }).first else {
                throw Failure.missingAttachmentDirectory
            }
            let folder = try Self.attachmentFolder(for: id)
            let roots = [OrgWorkspaceConfiguration.attachmentDirectory + "/" + folder,
                         try Self.resolve("data/" + folder, relativeTo: Self.parent(of: documentPath))]
            return try roots.map { try Self.resolve(name, relativeTo: $0) }
        case nil, "file":
            return [try Self.resolve(Self.localPath(target), relativeTo: Self.parent(of: documentPath))]
        default:
            throw Failure.invalidLink
        }
    }

    private static func imagePath(in target: String) throws -> String {
        switch scheme(in: target) {
        case "http", "https":
            // Query strings and fragments do not determine the image format.
            let url = try networkURL(target)
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw Failure.invalidLink
            }
            return try decode(components.percentEncodedPath)
        case "attachment":
            return try decode(String(target.dropFirst("attachment:".count)))
        case nil, "file":
            return try localPath(target)
        default:
            throw Failure.invalidLink
        }
    }

    private static func networkURL(_ value: String) throws -> URL {
        try validateEscapes(in: value)
        guard !hasControlCharacters(value), !hasControlCharacters(try decode(value)),
              let components = Self.urlComponents(preservingEscapesIn: value),
              ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
              components.user == nil, components.password == nil,
              let host = components.host, !host.isEmpty,
              !host.contains(where: { $0.isWhitespace }),
              !host.contains("\\"),
              components.port.map({ (1...65535).contains($0) }) ?? true,
              let url = components.url else { throw Failure.invalidLink }
        return url
    }

    private static func localPath(_ value: String) throws -> String {
        guard scheme(in: value) == "file" else {
            guard scheme(in: value) == nil else { throw Failure.invalidLink }
            return try decode(value)
        }
        let path = String(value.dropFirst("file:".count))
        guard path.hasPrefix("//") else { return try decode(path) }
        try validateEscapes(in: value)
        guard let components = Self.urlComponents(preservingEscapesIn: value),
              components.host == nil || components.host == "" || components.host?.lowercased() == "localhost",
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil else { throw Failure.invalidLink }
        return try decode(components.percentEncodedPath)
    }

    private static func urlComponents(preservingEscapesIn value: String) -> URLComponents? {
        // Foundation may escape existing '%' a second time when it encounters
        // an unescaped Unicode character or space in the same URL. Escape only
        // characters outside the URI grammar first; '%' has already been
        // validated by the caller, so existing escapes remain byte-for-byte.
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%")
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URLComponents(string: encoded)
    }

    private static func decode(_ value: String) throws -> String {
        try validateEscapes(in: value)
        guard let decoded = value.removingPercentEncoding,
              !decoded.isEmpty, !hasControlCharacters(decoded) else { throw Failure.invalidLink }
        return decoded
    }

    private static func validateEscapes(in value: String) throws {
        let bytes = Array(value.utf8)
        var index = 0
        func hexadecimal(_ byte: UInt8) -> Bool {
            (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
        }
        while index < bytes.count {
            if bytes[index] == 37 {
                guard index + 2 < bytes.count, hexadecimal(bytes[index + 1]), hexadecimal(bytes[index + 2]) else {
                    throw Failure.invalidLink
                }
                index += 3
            } else {
                index += 1
            }
        }
    }

    private static func hasControlCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private static func scheme(in value: String) -> String? {
        guard let colon = value.firstIndex(of: ":") else { return nil }
        let prefix = value[..<colon]
        guard let first = prefix.utf8.first,
              (65...90).contains(first) || (97...122).contains(first),
              prefix.utf8.allSatisfy({
                  (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                      || $0 == 43 || $0 == 45 || $0 == 46
              }) else { return nil }
        return prefix.lowercased()
    }

    private static func parent(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return slash == path.startIndex ? "/" : String(path[..<slash])
    }

    private static func resolve(_ path: String, relativeTo base: String) throws -> String {
        guard !path.isEmpty, !path.hasPrefix("~"), !hasControlCharacters(path),
              !hasControlCharacters(base) else { throw Failure.invalidLink }
        let combined = path.hasPrefix("/") ? path : (base.isEmpty ? path : base + "/" + path)
        let absolute = combined.hasPrefix("/")
        var components: [Substring] = []
        for component in combined.split(separator: "/") {
            switch component {
            case ".": continue
            case "..":
                guard !components.isEmpty else { throw Failure.outsideWorkspace }
                components.removeLast()
            default: components.append(component)
            }
        }
        guard !components.isEmpty else {
            if absolute { return "/" }
            throw Failure.invalidLink
        }
        return (absolute ? "/" : "") + components.joined(separator: "/")
    }

    private static func attachmentFolder(for id: String) throws -> String {
        let prefix = String(id.prefix(2))
        let remainder = String(id.dropFirst(2))
        guard !remainder.isEmpty, !id.contains("/"), !id.contains("\\"),
              !hasControlCharacters(id), ![".", ".."].contains(prefix),
              ![".", ".."].contains(remainder) else { throw Failure.invalidAttachmentID }
        return prefix + "/" + remainder
    }

    /// The parser stores headings and their following blocks as flat siblings.
    /// Recover the active outline ancestors at the link's original UTF-8 offset.
    private func attachmentScopes(in document: ParsedOrgDocument) -> [[String: String]] {
        let nodes = document.root.children
        func properties(in blocks: ArraySlice<ParsedOrgNode>) -> [String: String] {
            var result: [String: String] = [:]
            for drawer in blocks where drawer.type == "property_drawer" {
                for property in drawer.children where property.type == "property" {
                    guard let name = property.children.first(where: { $0.type == "property_name" })?.text,
                          let value = property.children.first(where: { $0.type == "property_value" })?.text
                            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { continue }
                    result[name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()] = value
                }
            }
            return result
        }

        let firstHeading = nodes.firstIndex { $0.type == "heading" } ?? nodes.endIndex
        let fileProperties = properties(in: nodes[..<firstHeading])
        var ancestors: [(level: Int, properties: [String: String])] = []
        for index in nodes.indices where nodes[index].type == "heading" {
            let heading = nodes[index]
            guard heading.startByte <= startByte else { break }
            let marker = heading.children.first { $0.type == "heading_marker" }?.text ?? heading.text
            let level = max(1, marker.prefix { $0 == "*" }.count)
            while ancestors.last.map({ $0.level >= level }) == true { ancestors.removeLast() }
            let followingStart = nodes.index(after: index)
            let end = nodes[followingStart...].firstIndex { $0.type == "heading" } ?? nodes.endIndex
            ancestors.append((level, properties(in: nodes[followingStart..<end])))
        }
        return [fileProperties] + ancestors.map(\.properties)
    }
}
