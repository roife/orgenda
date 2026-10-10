import XCTest
@testable import Orgenda

final class CloudAuthorizationTests: XCTestCase {
    private let providers: [StorageProvider] = [.oneDrive, .googleDrive, .dropbox]

    private var configuredInfo: [String: Any] {
        [
            "ORGENDAOneDriveClientID": "12345678-1234-1234-1234-123456789abc",
            "ORGENDAOneDriveRedirectURI": "orgenda-onedrive://oauth",
            "ORGENDAGoogleDriveClientID": "123456-test.apps.googleusercontent.com",
            "ORGENDAGoogleDriveRedirectURI": "com.googleusercontent.apps.123456-test:/oauth2redirect",
            "ORGENDADropboxClientID": "testappkey123",
            "ORGENDADropboxRedirectURI": "orgenda-dropbox://oauth",
            "CFBundleURLTypes": [["CFBundleURLSchemes": [
                "orgenda-onedrive", "com.googleusercontent.apps.123456-test", "orgenda-dropbox"
            ]]]
        ]
    }

    func testMissingConfigurationAndUnregisteredCallbackSchemesAreRejected() {
        for provider in providers {
            XCTAssertThrowsError(try CloudOAuthConfiguration.configured(provider, info: [:]))
            var info = configuredInfo
            info["CFBundleURLTypes"] = [["CFBundleURLSchemes": ["another-app"]]]
            XCTAssertThrowsError(try CloudOAuthConfiguration.configured(provider, info: info))
        }
    }

    func testEmptyUnexpandedAndMalformedClientIDsAreRejected() {
        for (provider, key) in [(StorageProvider.oneDrive, "ORGENDAOneDriveClientID"),
                                (.googleDrive, "ORGENDAGoogleDriveClientID"), (.dropbox, "ORGENDADropboxClientID")] {
            for value in ["", " ", "$(CLIENT_ID)", "key\ninjected", "invalid-id/"] {
                var info = configuredInfo
                info[key] = value
                XCTAssertThrowsError(try CloudOAuthConfiguration.configured(provider, info: info), value)
            }
        }
    }

    func testGoogleRejectsOldPlaceholderAndMismatchedReversedClientID() {
        for redirect in ["orgenda-google:/oauth2redirect", "com.googleusercontent.apps.other:/oauth2redirect",
                         "com.googleusercontent.apps.123456-test://oauth2redirect"] {
            var info = configuredInfo
            info["ORGENDAGoogleDriveRedirectURI"] = redirect
            info["CFBundleURLTypes"] = [["CFBundleURLSchemes": [URL(string: redirect)!.scheme!]]]
            XCTAssertThrowsError(try CloudOAuthConfiguration.configured(.googleDrive, info: info))
        }
    }

    func testRedirectCannotContainCredentialsQueryOrFragment() {
        for redirect in ["https://example.com/oauth", "file:///oauth", "orgenda-dropbox://user@oauth",
                         "orgenda-dropbox://oauth:123", "orgenda-dropbox://oauth?code=x", "orgenda-dropbox://oauth#x"] {
            var info = configuredInfo
            info["ORGENDADropboxRedirectURI"] = redirect
            XCTAssertThrowsError(try CloudOAuthConfiguration.configured(.dropbox, info: info))
        }
    }

    func testValidCallbackReturnsDecodedCodeForEveryProvider() throws {
        for provider in providers {
            let config = try CloudOAuthConfiguration.configured(provider, info: configuredInfo)
            let callback = URL(string: config.redirectURI + "?code=a%2Bb%26c&state=expected")!
            XCTAssertEqual(try config.authorizationCode(from: callback, expectedState: "expected"), "a+b&c")
        }
    }

    func testCallbackRejectsMissingWrongOrRepeatedStateAndAmbiguousCodes() throws {
        let config = try CloudOAuthConfiguration.configured(.dropbox, info: configuredInfo)
        for query in ["code=ok", "code=ok&state=wrong", "code=ok&state=expected&state=expected",
                      "code=ok&code=other&state=expected", "code=&state=expected", "state=expected",
                      "code=ok&error=access_denied&state=expected", "error=server_error&state=expected"] {
            XCTAssertThrowsError(try config.authorizationCode(from: URL(string: config.redirectURI + "?" + query)!, expectedState: "expected")) {
                XCTAssertEqual($0 as? StorageError, .authenticationRequired)
            }
        }
    }

    func testCallbackMustMatchTheWholeRedirectDestination() throws {
        let config = try CloudOAuthConfiguration.configured(.dropbox, info: configuredInfo)
        for redirect in ["other://oauth", "orgenda-dropbox://other", "orgenda-dropbox://oauth/other",
                         "orgenda-dropbox://user@oauth", "orgenda-dropbox://oauth:123"] {
            XCTAssertThrowsError(try config.authorizationCode(from: URL(string: redirect + "?code=ok&state=expected")!, expectedState: "expected"))
        }
        XCTAssertThrowsError(try config.authorizationCode(from: URL(string: config.redirectURI + "?code=ok&state=expected#fragment")!, expectedState: "expected"))
    }

    func testDecliningConsentCancelsOnlyWithMatchingState() throws {
        let config = try CloudOAuthConfiguration.configured(.googleDrive, info: configuredInfo)
        XCTAssertThrowsError(try config.authorizationCode(from: URL(string: config.redirectURI + "?error=access_denied&state=expected")!, expectedState: "expected")) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertThrowsError(try config.authorizationCode(from: URL(string: config.redirectURI + "?error=access_denied&state=wrong")!, expectedState: "expected")) {
            XCTAssertEqual($0 as? StorageError, .authenticationRequired)
        }
    }

    func testEveryProviderRequestsPKCEAndOfflineAccessWithoutClientSecret() throws {
        for provider in providers {
            let config = try CloudOAuthConfiguration.configured(provider, info: configuredInfo)
            XCTAssertEqual(config.provider, provider)
            XCTAssertEqual(config.authorizationURL.scheme, "https")
            XCTAssertEqual(config.tokenURL.scheme, "https")
            let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
            let request = try config.authorizationRequest(state: "state", verifier: verifier)
            let query = URLComponents(url: request, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertTrue(query.contains(.init(name: "code_challenge_method", value: "S256")))
            XCTAssertTrue(query.contains(.init(name: "state", value: "state")))
            XCTAssertTrue(query.contains(.init(name: "response_type", value: "code")))
            XCTAssertTrue(query.contains(.init(name: "code_challenge", value: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")))
            switch provider {
            case .oneDrive: XCTAssertTrue(config.scopes.split(separator: " ").contains("offline_access"))
            case .googleDrive: XCTAssertTrue(query.contains(.init(name: "access_type", value: "offline")))
            case .dropbox: XCTAssertTrue(query.contains(.init(name: "token_access_type", value: "offline")))
            default: XCTFail("Unexpected provider")
            }
            for parameters in [["grant_type": "refresh_token", "refresh_token": "test"],
                               ["grant_type": "authorization_code", "code": "a+b&c", "code_verifier": verifier]] {
                let body = String(decoding: config.tokenRequest(parameters).httpBody!, as: UTF8.self)
                XCTAssertFalse(body.contains("client_secret"), provider.rawValue)
                if parameters["code"] != nil { XCTAssertTrue(body.contains("code=a%2Bb%26c"), provider.rawValue) }
            }
        }
    }
}
