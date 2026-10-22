import Foundation
import Nuke

/// Adapts workspace attachments and remote URLs to Nuke's image pipeline.
enum OrgPreviewImageLoader {
    private static let maxBytes = 20 * 1024 * 1024

    static let pipeline: ImagePipeline = {
        let session = URLSessionConfiguration.default
        session.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 0)
        session.timeoutIntervalForRequest = 30
        session.timeoutIntervalForResource = 60
        let loader = DataLoader(configuration: session) { response in
            guard let url = response.url, OrgImageRedirectDelegate.isAllowed(url) else { return Failure.invalidURL }
            guard let response = response as? HTTPURLResponse else { return Failure.invalidResponse }
            guard (200...299).contains(response.statusCode) else { return Failure.httpStatus(response.statusCode) }
            return response.expectedContentLength > Int64(maxBytes) ? Failure.tooLarge : nil
        }
        loader.delegate = OrgImageRedirectDelegate()
        var configuration = ImagePipeline.Configuration(dataLoader: loader)
        // Keep attachment freshness in LocalStore and HTTP freshness in URLCache.
        configuration.imageCache = nil
        configuration.dataCache = nil
        configuration.isResumableDataEnabled = false
        configuration.maximumResponseDataSize = maxBytes
        return ImagePipeline(configuration: configuration)
    }()

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

    static func request(id: String, candidates: [String], localStore: LocalStore?) throws -> ImageRequest {
        var request: ImageRequest
        if let candidate = candidates.first, let url = URL(string: candidate),
           let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            guard OrgImageRedirectDelegate.isAllowed(url) else { throw Failure.invalidURL }
            var urlRequest = URLRequest(url: url)
            urlRequest.setValue("image/*", forHTTPHeaderField: "Accept")
            request = ImageRequest(urlRequest: urlRequest)
        } else {
            request = ImageRequest(id: id) {
                try await localData(candidates: candidates, localStore: localStore)
            }
        }
        request.imageID = id
        request.thumbnail = .init(maxPixelSize: 2048)
        return request
    }

    private static func localData(candidates: [String], localStore: LocalStore?) async throws -> Data {
        guard let localStore else { throw Failure.workspaceUnavailable }
        for candidate in candidates {
            try Task.checkCancellation()
            do {
                return try await localStore.readImageData(path: candidate, maxBytes: maxBytes)
            } catch {
                try Task.checkCancellation()
                // Alternate attachment locations may be tried only when a file is absent.
                if isMissingFile(error) { continue }
                throw error
            }
        }
        throw Failure.notFound
    }

    static func errorDescription(_ error: Error) -> String {
        var underlying = error
        if let error = error as? ImagePipeline.Error {
            switch error {
            case .dataLoadingFailed(let cause): underlying = cause
            case .dataDownloadExceededMaximumSize: underlying = Failure.tooLarge
            case .dataIsEmpty, .decoderNotRegistered, .decodingFailed: underlying = Failure.unsupportedFormat
            default: break
            }
        }
        if (underlying as? URLError)?.code == .appTransportSecurityRequiresSecureConnection {
            underlying = Failure.requiresHTTPS
        }
        return underlying.localizedDescription
    }

    private static func isMissingFile(_ error: Error) -> Bool {
        if case .http(404) = error as? StorageError { return true }
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
