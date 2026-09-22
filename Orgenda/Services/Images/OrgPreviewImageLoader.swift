import Foundation
import ImageIO
import UIKit

/// Loads preview assets away from the UI actor. Local files deliberately have
/// no image cache so replacing an attachment is reflected on the next preview.
actor OrgPreviewImageLoader {
    static let shared = OrgPreviewImageLoader()

    enum Failure: Error, Equatable, LocalizedError {
        case invalidURL
        case workspaceUnavailable
        case notFound
        case tooLarge
        case unsupportedFormat
        case requiresHTTPS
        case invalidResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return String(localized: "The image URL is invalid or contains embedded credentials.")
            case .workspaceUnavailable:
                return String(localized: "Connect the workspace folder to display this image.")
            case .notFound:
                return String(localized: "The image could not be found at this path.")
            case .tooLarge:
                return String(localized: "The image is too large to display.")
            case .unsupportedFormat:
                return String(localized: "This image format is unsupported or the image file is damaged.")
            case .requiresHTTPS:
                return String(localized: "This image requires a secure HTTPS connection.")
            case .invalidResponse:
                return String(localized: "The image server returned an invalid response.")
            case .httpStatus(let status):
                if status == 404 {
                    return String(localized: "The image was not found on the server (404).")
                }
                return String(localized: "The image server returned HTTP \(status).")
            }
        }
    }

    private let session: URLSession
    private let maxBytes: Int
    private let maxPixelDimension: Int

    init(session: URLSession? = nil, maxBytes: Int = 20 * 1024 * 1024, maxPixelDimension: Int = 2048) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            // Honor server freshness headers and avoid an unbounded decoded
            // image cache or retaining downloaded attachments on disk.
            configuration.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 0)
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: configuration)
        }
        self.maxBytes = max(0, maxBytes)
        self.maxPixelDimension = max(1, maxPixelDimension)
    }

    func load(candidates: [String], fileStore: WorkspaceFileStore?, workspaceID: UUID) async throws -> UIImage {
        try Task.checkCancellation()
        // The workspace ID is part of the call contract for view task identity.
        // There is no local cache shared across workspaces.
        _ = workspaceID
        for candidate in candidates {
            try Task.checkCancellation()
            let data: Data
            if let url = URL(string: candidate), let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                guard OrgImageRedirectDelegate.isAllowed(url) else { throw Failure.invalidURL }
                data = try await remoteData(from: url)
            } else {
                guard let fileStore else { throw Failure.workspaceUnavailable }
                do {
                    data = try await fileStore.readImageData(path: candidate, maxBytes: maxBytes)
                } catch {
                    try Task.checkCancellation()
                    // Alternate attachment locations may be tried only when a
                    // file is absent. Never hide permission, size, or path errors.
                    if Self.isMissingFile(error) { continue }
                    throw error
                }
            }
            try Task.checkCancellation()
            let image = try decode(data)
            try Task.checkCancellation()
            return image
        }
        throw Failure.notFound
    }

    private func remoteData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let redirectDelegate = OrgImageRedirectDelegate()
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: redirectDelegate)
            // This also cancels a download as soon as its headers or streamed
            // body exceed the budget, instead of leaving it in the background.
            defer { bytes.task.cancel() }
            try Task.checkCancellation()
            guard let finalURL = response.url, OrgImageRedirectDelegate.isAllowed(finalURL) else {
                throw Failure.invalidURL
            }
            guard let response = response as? HTTPURLResponse else { throw Failure.invalidResponse }
            guard (200...299).contains(response.statusCode) else { throw Failure.httpStatus(response.statusCode) }
            guard response.expectedContentLength <= Int64(maxBytes) else { throw Failure.tooLarge }

            return try await withTaskCancellationHandler {
                var data = Data()
                if response.expectedContentLength > 0 {
                    data.reserveCapacity(Int(response.expectedContentLength))
                }
                for try await byte in bytes {
                    try Task.checkCancellation()
                    guard data.count < maxBytes else { throw Failure.tooLarge }
                    data.append(byte)
                }
                return data
            } onCancel: {
                bytes.task.cancel()
            }
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            if (error as? URLError)?.code == .appTransportSecurityRequiresSecureConnection {
                throw Failure.requiresHTTPS
            }
            throw error
        }
    }

    private func decode(_ data: Data) throws -> UIImage {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0 else { throw Failure.unsupportedFormat }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw Failure.unsupportedFormat
        }
        return UIImage(cgImage: image)
    }

    private static func isMissingFile(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain,
           error.code == CocoaError.fileReadNoSuchFile.rawValue || error.code == CocoaError.fileNoSuchFile.rawValue {
            return true
        }
        if error.domain == NSPOSIXErrorDomain, error.code == Int(ENOENT) { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isMissingFile(underlying)
        }
        return false
    }
}

/// Validate every redirect before URLSession sends its next request. The
/// standard system trust and App Transport Security policy remain in force.
private final class OrgImageRedirectDelegate: NSObject, URLSessionTaskDelegate {
    static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return false }
        return true
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, Self.isAllowed(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
