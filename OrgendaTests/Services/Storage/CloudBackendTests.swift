import CryptoKit
import XCTest
@testable import Orgenda

@MainActor
final class CloudBackendTests: XCTestCase {
    override func tearDown() {
        StorageMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testCloudConnectionPreservesExplicitEmailAndIdentity() throws {
        for provider in [StorageProvider.googleDrive, .dropbox, .oneDrive] {
            let original = StorageConnection(provider: provider, displayName: "Orgenda",
                accountID: "account-123", accountEmail: " alice@example.com \n", rootID: "root-123", credentialKey: "saved-key")
            let data = try JSONEncoder().encode(original)
            let restored = try JSONDecoder().decode(StorageConnection.self, from: data)
            XCTAssertEqual(restored.accountEmail, original.accountEmail)
            XCTAssertEqual(restored.emailAddress, "alice@example.com")
            XCTAssertEqual(restored.providerSummary, "alice@example.com")
            XCTAssertEqual(restored.identity, original.identity)
            XCTAssertEqual(restored.credentialKey, "saved-key")
        }
    }

    func testCloudAccountNeverDisplaysNamesOrInternalIDsAsEmail() {
        for provider in [StorageProvider.googleDrive, .dropbox, .oneDrive] {
            var connection = StorageConnection(provider: provider, displayName: "Orgenda",
                accountID: "internal-account-id", accountName: "Alice Example", rootID: "root")
            XCTAssertNil(connection.emailAddress)
            XCTAssertFalse(connection.providerSummary.contains("Alice"))
            XCTAssertFalse(connection.providerSummary.contains("internal-account-id"))
            connection.accountName = nil
            connection.accountID = "id-that-looks-like@email.example"
            XCTAssertNil(connection.emailAddress)
            connection.accountName = "name-that-looks-like@email.example"
            XCTAssertNil(connection.emailAddress)
        }
    }

    func testExplicitEmailSurvivesPersistenceIndependentlyOfAccountName() throws {
        let connection = StorageConnection(provider: .googleDrive, displayName: "Google Drive · Orgenda",
            accountID: "account-123", accountName: "old@example.com", accountEmail: " new@example.com ", rootID: "root")
        let restored = try JSONDecoder().decode(StorageConnection.self, from: JSONEncoder().encode(connection))
        XCTAssertEqual(restored.emailAddress, "new@example.com")
        XCTAssertEqual(restored.providerSummary, "new@example.com")
        XCTAssertEqual(restored.storageSummary, "Orgenda")
        XCTAssertEqual(restored.identity, connection.identity)
    }

    func testOneDriveReadsOnlyEmailFromProfile() async throws {
        StorageMockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1.0/me")
            let fields = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(fields?.first(where: { $0.name == "$select" })?.value, "mail")
            return .json(["mail": "alice@example.com", "displayName": "Alice", "userPrincipalName": "alice@tenant.example"])
        }
        let client = CloudHTTPClient(transport: transport, tokens: TestTokenSource(), allowedHosts: ["graph.microsoft.com"])
        let email = try await CloudConnectionFactory.oneDriveAccountEmail(client: client)
        XCTAssertEqual(email, "alice@example.com")
    }

    func testOneDriveMissingMailDoesNotFallBackToPrincipalName() async throws {
        StorageMockURLProtocol.handler = { _ in
            .json(["mail": NSNull(), "displayName": "Alice", "userPrincipalName": "alice@tenant.example"])
        }
        let client = CloudHTTPClient(transport: transport, tokens: TestTokenSource(), allowedHosts: ["graph.microsoft.com"])
        let email = try await CloudConnectionFactory.oneDriveAccountEmail(client: client)
        XCTAssertNil(email)
    }

    func testResponseBodyLimitIsEnforcedWithoutContentLength() async throws {
        StorageMockURLProtocol.handler = { _ in .init(body: Data(repeating: 42, count: 4096)) }
        do {
            _ = try await transport.send(URLRequest(url: URL(string: "https://dav.example/test")!), maxBytes: 512)
            XCTFail("An unbounded response was accepted")
        } catch { XCTAssertEqual(error as? StorageError, .tooLarge) }
    }

    func testDeclaredResponseLengthIsRejectedBeforeReading() async throws {
        StorageMockURLProtocol.handler = { _ in .init(headers: ["Content-Length": "5000"], body: Data()) }
        do {
            _ = try await transport.send(URLRequest(url: URL(string: "https://dav.example/test")!), maxBytes: 512)
            XCTFail("Oversized content-length was accepted")
        } catch { XCTAssertEqual(error as? StorageError, .tooLarge) }
    }

    func testRetryAfterSecondsAndHTTPDateBecomeBackoff() throws {
        XCTAssertThrowsError(try StorageHTTPResponse(status: 429, headers: ["retry-after": "120"], data: Data()).checked()) {
            XCTAssertEqual($0 as? StorageError, .throttled(120))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let date = formatter.string(from: Date().addingTimeInterval(90))
        XCTAssertThrowsError(try StorageHTTPResponse(status: 503, headers: ["retry-after": date], data: Data()).checked()) {
            guard case .throttled(let delay) = $0 as? StorageError else { return XCTFail("Missing server backoff") }
            XCTAssertGreaterThan(delay, 87)
            XCTAssertLessThanOrEqual(delay, 90)
        }
    }

    func testRedirectsKeepWritesInsideDAVRootAndRequirePreservingStatus() {
        let root = URL(string: "https://dav.example/org/")!
        var request = URLRequest(url: root.appendingPathComponent("note.org"))
        request.httpMethod = "PUT"
        XCTAssertFalse(StorageHTTP.redirectAllowed(request: request, target: root.appendingPathComponent("canonical.org"), status: 303, pathRoot: root))
        XCTAssertTrue(StorageHTTP.redirectAllowed(request: request, target: root.appendingPathComponent("canonical.org"), status: 307, pathRoot: root))
        for target in ["https://dav.example/other/note.org", "https://dav.example/org-copy/note.org",
                       "https://dav.example/org/../outside.org", "https://dav.example/org/%2E%2E/outside.org",
                       "https://untrusted.example/org/note.org", "http://dav.example/org/note.org"] {
            XCTAssertFalse(StorageHTTP.redirectAllowed(request: request, target: URL(string: target)!, status: 307, pathRoot: root), target)
        }
        request.httpMethod = "GET"
        XCTAssertTrue(StorageHTTP.redirectAllowed(request: request, target: root, status: 301, pathRoot: root))
    }

    func testPKCEAndOAuthParametersUseNativePublicClientFlow() throws {
        let config = CloudOAuthConfiguration(provider: .googleDrive, clientID: "client",
                                              redirectURI: "orgenda-test:/oauth2redirect",
                                              authorizationURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                                              tokenURL: URL(string: "https://oauth2.googleapis.com/token")!, scopes: "drive")
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let url = try config.authorizationRequest(state: "state", verifier: verifier)
        let query = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
        XCTAssertEqual(query["code_challenge"], "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["access_type"], "offline")
        let request = config.tokenRequest(["grant_type": "authorization_code", "code": "a+b&c", "code_verifier": verifier])
        let body = String(decoding: request.httpBody!, as: UTF8.self)
        XCTAssertTrue(body.contains("code=a%2Bb%26c"))
        XCTAssertFalse(body.contains("client_secret"))
    }

    func testBearerTokenIsRefreshedOnceAfterUnauthorized() async throws {
        let tokens = TestTokenSource()
        StorageMockURLProtocol.handler = { request in
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer initial" { return .init(status: 401) }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer refreshed")
            return .json(["value": []])
        }
        let client = CloudHTTPClient(transport: transport, tokens: tokens, allowedHosts: ["graph.microsoft.com"])
        _ = try await client.json(URL(string: "https://graph.microsoft.com/v1.0/test")!)
        let refreshes = await tokens.refreshes
        XCTAssertEqual(refreshes, 1)
    }

    func testBearerTokenCannotBeSentToPaginationHostOutsideProvider() async throws {
        StorageMockURLProtocol.handler = { _ in XCTFail("Unexpected network request"); return .init() }
        do {
            _ = try await googleClient.send(URLRequest(url: URL(string: "https://untrusted.example/page")!))
            XCTFail("The untrusted host was accepted")
        } catch { XCTAssertEqual(error as? StorageError, .invalidResponse) }
    }

    func testWebDAVParsesNamespacesAndPreservesHiddenBinaryEntries() throws {
        let parser = WebDAVMultistatusParser()
        let xml = """
        <multistatus xmlns="DAV:"><response><href>/org/.attach/photo.png</href><propstat><prop><getetag>"revision"</getetag><getcontentlength>42</getcontentlength><resourcetype/></prop><status>HTTP/1.1 200 OK</status></propstat></response></multistatus>
        """
        let files = try parser.parse(Data(xml.utf8), root: URL(string: "https://dav.example/org/")!)
        XCTAssertEqual(files.first?.path, ".attach/photo.png")
        XCTAssertEqual(files.first?.revision, "\"revision\"")
        XCTAssertEqual(files.first?.size, 42)
    }

    func testWebDAVRejectsEscapingHrefAndFailedResourceStatus() throws {
        for href in ["https://other.example/org/note.org", "/outside/note.org", "/org/../outside.org"] {
            let xml = "<d:multistatus xmlns:d=\"DAV:\"><d:response><d:href>\(href)</d:href><d:propstat><d:prop><d:getetag>\"x\"</d:getetag></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>"
            XCTAssertThrowsError(try WebDAVMultistatusParser().parse(Data(xml.utf8), root: URL(string: "https://dav.example/org/")!))
        }
        let denied = "<d:multistatus xmlns:d=\"DAV:\"><d:response><d:href>/org/secret.org</d:href><d:status>HTTP/1.1 403 Forbidden</d:status></d:response></d:multistatus>"
        XCTAssertThrowsError(try WebDAVMultistatusParser().parse(Data(denied.utf8), root: URL(string: "https://dav.example/org/")!))
    }

    func testWebDAVRequiresSuccessfulResourceTypeAndDirectoryRoot() async throws {
        let missingType = "<d:multistatus xmlns:d=\"DAV:\"><d:response><d:href>/org/</d:href><d:propstat><d:prop><d:getetag>\"x\"</d:getetag></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>"
        XCTAssertThrowsError(try WebDAVMultistatusParser().parse(Data(missingType.utf8), root: URL(string: "https://dav.example/org/")!))
        let fileRoot = "<d:multistatus xmlns:d=\"DAV:\"><d:response><d:href>/org/</d:href><d:propstat><d:prop><d:resourcetype/><d:getetag>\"x\"</d:getetag></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>"
        var calls = 0
        StorageMockURLProtocol.handler = { _ in calls += 1; return .init(status: 207, body: Data(fileRoot.utf8)) }
        do { _ = try await WebDAVBackend(rootURL: URL(string: "https://dav.example/org/")!, transport: transport).scan(cursor: nil); XCTFail() }
        catch { XCTAssertEqual(error as? StorageError, .rootUnavailable) }
        XCTAssertEqual(calls, 1)
    }

    func testWebDAVExistingUploadUsesExactETagAndNeverRetries412() async throws {
        var requests = 0
        StorageMockURLProtocol.handler = { request in
            requests += 1
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "\"base\"")
            XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"))
            return .init(status: 412)
        }
        let backend = WebDAVBackend(rootURL: URL(string: "https://dav.example/org/")!, transport: transport)
        do {
            _ = try await backend.upload(path: "note.org", data: Data("edit".utf8),
                                         existing: .init(id: "note.org", path: "note.org", isDirectory: false, revision: "\"base\""), operationID: UUID())
            XCTFail("A stale write succeeded")
        } catch { XCTAssertEqual(error as? StorageError, .conflict("note.org")) }
        XCTAssertEqual(requests, 1)
    }

    func testWebDAVCreateAndMoveNeverReplaceDestination() async throws {
        StorageMockURLProtocol.handler = { request in
            if request.httpMethod == "PUT" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "*")
            } else {
                XCTAssertEqual(request.httpMethod, "MOVE")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Overwrite"), "F")
                XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "\"base\"")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Destination"), "https://dav.example/org/new.org")
            }
            return .init(status: 412)
        }
        let backend = WebDAVBackend(rootURL: URL(string: "https://dav.example/org/")!, transport: transport)
        do { _ = try await backend.upload(path: "new.org", data: Data(), existing: nil, operationID: UUID()); XCTFail() }
        catch { XCTAssertEqual(error as? StorageError, .conflict("new.org")) }
        do { _ = try await backend.move(.init(id: "old.org", path: "old.org", isDirectory: false, revision: "\"base\""), to: "new.org"); XCTFail() }
        catch { XCTAssertEqual(error as? StorageError, .conflict("new.org")) }
    }

    func testDropboxFollowsAllPagesBeforeReturningFullSnapshot() async throws {
        StorageMockURLProtocol.handler = { request in
            switch request.url!.path {
            case "/2/files/get_metadata": return .json([".tag": "folder", "id": "id:root", "path_display": "/Workspace"])
            case "/2/files/list_folder":
                return .json(["entries": [[".tag": "folder", "id": "id:hidden", "path_display": "/Workspace/.attach"]], "cursor": "page2", "has_more": true])
            case "/2/files/list_folder/continue":
                XCTAssertEqual(try Self.body(request)["cursor"] as? String, "page2")
                return .json(["entries": [[".tag": "file", "id": "id:image", "path_display": "/Workspace/.attach/image.png", "rev": "rev1", "size": 7]], "cursor": "done", "has_more": false])
            default: XCTFail("Unexpected endpoint"); return .init(status: 500)
            }
        }
        let backend = DropboxBackend(rootID: "id:root", client: dropboxClient)
        let scan = try await backend.scan(cursor: nil)
        XCTAssertTrue(scan.isFullSnapshot)
        XCTAssertEqual(scan.files.map(\.path), [".attach", ".attach/image.png"])
        XCTAssertEqual(scan.cursor, "done")
    }

    func testDropboxUploadUsesRevisionAndStrictConflict() async throws {
        StorageMockURLProtocol.handler = { request in
            if request.url!.path == "/2/files/get_metadata" {
                let requested = try Self.body(request)["path"] as? String
                if requested == "id:root" { return .json([".tag": "folder", "id": "id:root", "path_display": "/Workspace"]) }
                return .json([".tag": "file", "id": "id:note", "path_display": "/Workspace/中文.org", "rev": "base"])
            }
            let header = request.value(forHTTPHeaderField: "Dropbox-API-Arg")!
            XCTAssertTrue(header.contains("\\u"))
            let args = try JSONSerialization.jsonObject(with: Data(header.utf8)) as! [String: Any]
            XCTAssertEqual((args["mode"] as? [String: String])?["update"], "base")
            XCTAssertEqual(args["strict_conflict"] as? Bool, true)
            XCTAssertEqual(args["autorename"] as? Bool, false)
            return .init(status: 409)
        }
        let backend = DropboxBackend(rootID: "id:root", client: dropboxClient)
        do {
            _ = try await backend.upload(path: "中文.org", data: Data("edit".utf8),
                                         existing: .init(id: "id:note", path: "中文.org", isDirectory: false, revision: "base"), operationID: UUID())
            XCTFail()
        } catch { XCTAssertEqual(error as? StorageError, .conflict("中文.org")) }
    }

    func testDropboxCoalescesRepeatedFileUpdatesAcrossDeltaPages() async throws {
        StorageMockURLProtocol.handler = { request in
            if request.url!.path == "/2/files/get_metadata" { return .json([".tag": "folder", "id": "id:root", "path_display": "/Workspace"]) }
            let cursor = try? Self.body(request)["cursor"] as? String
            let revision: String, next: String, more: Bool
            if request.url!.path == "/2/files/list_folder" { revision = "v1"; next = "base"; more = false }
            else if cursor == "base" { revision = "v2"; next = "page2"; more = true }
            else { revision = "v3"; next = "done"; more = false }
            return .json(["entries": [[".tag": "file", "id": "id:file", "path_display": "/Workspace/note.org", "rev": revision]],
                          "cursor": next, "has_more": more])
        }
        let backend = DropboxBackend(rootID: "id:root", client: dropboxClient)
        let first = try await backend.scan(cursor: nil)
        let delta = try await backend.scan(cursor: first.cursor)
        XCTAssertFalse(delta.isFullSnapshot)
        XCTAssertEqual(delta.files.count, 1)
        XCTAssertEqual(delta.files.first?.revision, "v3")
    }

    func testGoogleUsesV2ConditionalMultipartWrite() async throws {
        var uploads = 0
        StorageMockURLProtocol.handler = { request in
            if request.httpMethod == "GET" { return .json(Self.googleMetadata(request.url!.lastPathComponent)) }
            uploads += 1
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url!.path, "/upload/drive/v2/files/note")
            XCTAssertTrue(request.url!.query!.contains("uploadType=multipart"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "\"base\"")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/related"))
            return .init(status: 412)
        }
        let backend = GoogleDriveBackend(rootID: "root", client: googleClient)
        do {
            _ = try await backend.upload(path: "note.org", data: Data("edit".utf8),
                                         existing: .init(id: "note", path: "note.org", isDirectory: false, revision: "\"base\""), operationID: UUID())
            XCTFail()
        } catch { XCTAssertEqual(error as? StorageError, .conflict("note.org")) }
        XCTAssertEqual(uploads, 1)
    }

    func testGoogleResumablePropagatesConflictAtCommit() async throws {
        var initiated = false
        StorageMockURLProtocol.handler = { request in
            if request.httpMethod == "GET" { return .json(Self.googleMetadata(request.url!.lastPathComponent)) }
            if request.url!.path == "/upload/drive/v2/files/note" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "\"base\"")
                XCTAssertTrue(request.url!.query!.contains("resumable"))
                initiated = true
                return .init(headers: ["Location": "https://www.googleapis.com/upload/session"])
            }
            XCTAssertTrue(initiated)
            XCTAssertNotNil(request.value(forHTTPHeaderField: "Content-Range"))
            return .init(status: 412)
        }
        let backend = GoogleDriveBackend(rootID: "root", client: googleClient)
        do {
            _ = try await backend.upload(path: "note.org", data: Data(repeating: 65, count: 6 * 1024 * 1024),
                                         existing: .init(id: "note", path: "note.org", isDirectory: false, revision: "\"base\""), operationID: UUID())
            XCTFail()
        } catch { XCTAssertEqual(error as? StorageError, .conflict("note.org")) }
    }

    func testGoogleScanThrowsInsteadOfReturningPartialPages() async throws {
        StorageMockURLProtocol.handler = { request in
            if request.url!.lastPathComponent == "root" { return .json(Self.googleMetadata("root")) }
            if request.url!.lastPathComponent == "about" { return .json(["largestChangeId": "10"]) }
            if request.url!.query!.contains("pageToken=next") { return .init(status: 503) }
            return .json(["items": [Self.googleMetadata("note")], "nextPageToken": "next"])
        }
        do { _ = try await GoogleDriveBackend(rootID: "root", client: googleClient).scan(cursor: nil); XCTFail() }
        catch { XCTAssertEqual(error as? StorageError, .throttled(60)) }
    }

    func testGoogleEmptyWorkspaceAndIDOnlyIncrementalCheck() async throws {
        var enumerations = 0
        StorageMockURLProtocol.handler = { request in
            switch request.url!.lastPathComponent {
            case "root": return .json(Self.googleMetadata("root"))
            case "about": return .json(["largestChangeId": "10"])
            case "changes":
                let fields = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "fields" }!.value!
                XCTAssertEqual(fields, "items(id,fileId,deleted),largestChangeId,nextPageToken")
                return .json(["largestChangeId": "10"])
            default: enumerations += 1; return .json([:]) // Google omits empty items.
            }
        }
        let backend = GoogleDriveBackend(rootID: "root", client: googleClient)
        let first = try await backend.scan(cursor: nil)
        XCTAssertTrue(first.files.isEmpty)
        XCTAssertEqual(first.cursor, "11")
        let second = try await backend.scan(cursor: first.cursor)
        XCTAssertFalse(second.isFullSnapshot)
        XCTAssertEqual(enumerations, 1)
    }

    func testOneDriveDeltaRebuildsDescendantPathsAfterFolderRename() async throws {
        StorageMockURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/items/root") { return .json(["id": "root", "folder": [:], "eTag": "rootrev"]) }
            if request.url!.path == "/delta-next" {
                return .json(["value": [["id": "folder", "name": "renamed", "folder": [:], "eTag": "f2", "parentReference": ["id": "root"]]],
                              "@odata.deltaLink": "https://graph.microsoft.com/delta-final"])
            }
            return .json(["value": [["id": "folder", "name": "notes", "folder": [:], "eTag": "f1", "parentReference": ["id": "root"]],
                                      ["id": "file", "name": "a.org", "file": [:], "eTag": "v1", "parentReference": ["id": "folder"]]],
                          "@odata.deltaLink": "https://graph.microsoft.com/delta-next"])
        }
        let client = CloudHTTPClient(transport: transport, tokens: TestTokenSource(), allowedHosts: ["graph.microsoft.com"])
        let backend = OneDriveBackend(driveID: "drive", rootID: "root", client: client)
        let first = try await backend.scan(cursor: nil)
        let second = try await backend.scan(cursor: first.cursor)
        XCTAssertTrue(second.isFullSnapshot)
        XCTAssertEqual(Set(second.files.map(\.path)), ["renamed", "renamed/a.org"])
        XCTAssertEqual(second.files.first(where: { $0.id == "file" })?.revision, "v1")
    }

    func testOneDriveZeroByteWritesRetainPreconditionsAndCreateFailPolicy() async throws {
        var contentWrites = 0
        StorageMockURLProtocol.handler = { request in
            if request.httpMethod == "GET" {
                if request.url!.lastPathComponent == "root" { return .json(["id": "root", "folder": [:], "eTag": "rootrev"]) }
                return .json(["id": "note", "name": "note.org", "file": [:], "eTag": "\"base\"", "parentReference": ["id": "root"]])
            }
            contentWrites += 1
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertTrue(request.url!.path.hasSuffix("/content"))
            if request.url!.path.contains("/items/note/") {
                XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "\"base\"")
            } else {
                XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "*")
                XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems?.first?.value, "fail")
            }
            return .init(status: 412)
        }
        let client = CloudHTTPClient(transport: transport, tokens: TestTokenSource(), allowedHosts: ["graph.microsoft.com"])
        let backend = OneDriveBackend(driveID: "drive", rootID: "root", client: client)
        do {
            _ = try await backend.upload(path: "note.org", data: Data(), existing: .init(id: "note", path: "note.org", isDirectory: false, revision: "\"base\""), operationID: UUID())
            XCTFail()
        } catch { XCTAssertEqual(error as? StorageError, .conflict("note.org")) }
        do { _ = try await backend.upload(path: "new.org", data: Data(), existing: nil, operationID: UUID()); XCTFail() }
        catch { XCTAssertEqual(error as? StorageError, .conflict("new.org")) }
        XCTAssertEqual(contentWrites, 2)
    }

    private var transport: StorageURLSessionTransport { .init(protocolClasses: [StorageMockURLProtocol.self]) }
    private var googleClient: CloudHTTPClient { .init(transport: transport, tokens: TestTokenSource(), allowedHosts: ["www.googleapis.com"]) }
    private var dropboxClient: CloudHTTPClient { .init(transport: transport, tokens: TestTokenSource(), allowedHosts: ["api.dropboxapi.com", "content.dropboxapi.com"]) }
    private static func body(_ request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let body = request.httpBody { data = body }
        else if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var output = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                output.append(buffer, count: count)
            }
            data = output
        } else { data = Data() }
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
    private static func googleMetadata(_ id: String) -> [String: Any] {
        ["id": id, "title": id == "root" ? "Orgenda" : "note.org", "mimeType": id == "root" ? "application/vnd.google-apps.folder" : "application/octet-stream",
         "etag": "\"base\"", "parents": [["id": id == "root" ? "mydrive" : "root"]]]
    }
}

private actor TestTokenSource: StorageAccessTokenSource {
    var refreshes = 0
    func accessToken(forceRefresh: Bool) async throws -> String {
        if forceRefresh { refreshes += 1; return "refreshed" }
        return "initial"
    }
}

private final class StorageMockURLProtocol: URLProtocol {
    struct Reply {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
        static func json(_ object: [String: Any]) -> Self { .init(headers: ["Content-Type": "application/json"], body: try! JSONSerialization.data(withJSONObject: object)) }
    }
    static var handler: ((URLRequest) throws -> Reply)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw StorageError.invalidResponse }
            let reply = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !reply.body.isEmpty { client?.urlProtocol(self, didLoad: reply.body) }
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
