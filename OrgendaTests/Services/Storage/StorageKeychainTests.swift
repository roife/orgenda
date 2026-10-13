import XCTest
@testable import Orgenda

final class StorageKeychainTests: XCTestCase {
    func testCredentialRoundTripAndPasswordReplacement() throws {
        let key = UUID().uuidString
        defer { try? StorageKeychain.remove(key) }
        try StorageKeychain.write(StorageCredential(username: "alice", password: "original"), key: key)
        let original = try StorageKeychain.read(key)
        XCTAssertEqual(original.username, "alice")
        XCTAssertEqual(original.password, "original")

        try StorageKeychain.write(StorageCredential(username: "alice", password: "replacement"), key: key)
        let replacement = try StorageKeychain.read(key)
        XCTAssertEqual(replacement.username, "alice")
        XCTAssertEqual(replacement.password, "replacement")
    }

    func testRemovingOneConnectionPreservesOtherCredentials() throws {
        let firstKey = UUID().uuidString, secondKey = UUID().uuidString
        defer {
            try? StorageKeychain.remove(firstKey)
            try? StorageKeychain.remove(secondKey)
        }
        try StorageKeychain.write(StorageCredential(username: "first", password: "first-password"), key: firstKey)
        try StorageKeychain.write(StorageCredential(username: "second", password: "second-password"), key: secondKey)
        try StorageKeychain.remove(firstKey)
        XCTAssertThrowsError(try StorageKeychain.read(firstKey)) {
            XCTAssertEqual($0 as? StorageError, .authenticationRequired)
        }
        let remaining = try StorageKeychain.read(secondKey)
        XCTAssertEqual(remaining.username, "second")
        XCTAssertEqual(remaining.password, "second-password")
        XCTAssertNoThrow(try StorageKeychain.remove(firstKey))
    }

    func testMissingCredentialsRequireAuthentication() {
        XCTAssertThrowsError(try StorageKeychain.read(UUID().uuidString)) {
            XCTAssertEqual($0 as? StorageError, .authenticationRequired)
        }
    }
}
