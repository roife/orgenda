import XCTest
@testable import Orgenda

@MainActor
final class OrgPreviewImageReferenceTests: XCTestCase {
    func testBracketImagesKeepDescriptionAndOriginalUnicodeByteOffset() throws {
        let prefix = "正文🙂\n"
        let document = try parse(prefix + "[[file:图片/猫%20咪.PNG][一只猫]]\n")
        let reference = try XCTUnwrap(references(in: document).first)

        XCTAssertEqual(reference.target, "file:图片/猫%20咪.PNG")
        XCTAssertEqual(reference.label, "一只猫")
        XCTAssertEqual(reference.startByte, prefix.utf8.count)
        XCTAssertEqual(try reference.candidates(documentPath: document.path, document: document),
                       ["notes/图片/猫 咪.PNG"])
    }

    func testImageFormatsAndQueryStringsAreDetectedFromThePath() throws {
        let formats = ["png", "jpg", "jpeg", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp", "avif", "svg"]
        for format in formats {
            XCTAssertNotNil(OrgPreviewImageReference.from(link("file:images/photo.\(format.uppercased())")))
        }
        let network = try XCTUnwrap(OrgPreviewImageReference.from(link("https://example.com/猫.PNG?token=a.jpg#preview")))
        XCTAssertEqual(network.label, "猫.PNG")
        XCTAssertNotNil(OrgPreviewImageReference.from(link("https://example.com/photo%2EPNG?token=1")))
        XCTAssertNil(OrgPreviewImageReference.from(link("https://example.com/page?image=photo.png")))
        XCTAssertNil(OrgPreviewImageReference.from(link("file:notes.org")))
        XCTAssertNil(OrgPreviewImageReference.from(link("ftp://example.com/photo.png")))
        XCTAssertNil(OrgPreviewImageReference.from(link("https://user:password@example.com/photo.png")))
        XCTAssertNil(OrgPreviewImageReference.from(link("file:photo.png", type: "plain_link")))
        XCTAssertNil(OrgPreviewImageReference.from(link("file:photo.png", type: "angle_link")))
    }

    func testRelativePathsUseTheOrgDirectoryAndNormalizeDotSegments() throws {
        let cases = [
            "images/photo.png": "notes/images/photo.png",
            "file:images/photo.png": "notes/images/photo.png",
            "file:../images/./photo.png": "images/photo.png",
            "./images/../photo.png": "notes/photo.png",
            "FILE:../.attach/ab/cd/photo.png": ".attach/ab/cd/photo.png",
            "file:照片/猫%20咪.png": "notes/照片/猫 咪.png",
            "file:images/a%23b%3Fc.png": "notes/images/a#b?c.png",
        ]
        for (target, expected) in cases {
            XCTAssertEqual(try reference(target).candidates(documentPath: "notes/page.org", document: nil),
                           [expected], target)
        }
    }

    func testPercentEncodingIsDecodedExactlyOnceAndDocumentPathIsLiteral() throws {
        XCTAssertEqual(try reference("file:%252e%252e/100%2525.png")
            .candidates(documentPath: "notes/page.org", document: nil), ["notes/%2e%2e/100%25.png"])
        XCTAssertEqual(try reference("file:photo%20one.png")
            .candidates(documentPath: "100%25/page.org", document: nil), ["100%25/photo one.png"])
        XCTAssertEqual(try reference("file:///workspace/photo%2520one.png")
            .candidates(documentPath: "page.org", document: nil), ["/workspace/photo%20one.png"])
        XCTAssertEqual(try reference("file://localhost/workspace/图片/photo%2520one.png")
            .candidates(documentPath: "page.org", document: nil), ["/workspace/图片/photo%20one.png"])
    }

    func testAbsolutePathsAndLocalFileURLsAreRetainedForWorkspaceAccessChecks() throws {
        for target in ["/workspace/图片/a b.png", "file:/workspace/图片/a b.png",
                       "file:///workspace/%E5%9B%BE%E7%89%87/a%20b.png",
                       "file://localhost/workspace/图片/a%20b.png"] {
            XCTAssertEqual(try reference(target).candidates(documentPath: "notes/page.org", document: nil),
                           ["/workspace/图片/a b.png"], target)
        }
        XCTAssertEqual(try reference("../photo.png")
            .candidates(documentPath: "/workspace/notes/page.org", document: nil), ["/workspace/photo.png"])
    }

    func testParentTraversalCannotEscapeTheWorkspace() {
        for target in ["../../photo.png", "file:../../photo.png", "file:%2E%2E/%2e%2e/photo.png",
                       "file:images/../../../photo.png"] {
            XCTAssertThrowsError(try reference(target).candidates(documentPath: "notes/page.org", document: nil)) {
                XCTAssertEqual($0 as? OrgPreviewImageReference.Failure, .outsideWorkspace, target)
            }
        }
        XCTAssertThrowsError(try reference("../photo.png").candidates(documentPath: "page.org", document: nil))
    }

    func testMalformedAndUnsupportedLinksDoNotBecomeLocalPaths() {
        let targets = ["", "file:", "file:photo%2.png", "file:photo%GG.png", "file:photo%FF.png",
                       "file:photo%00.png", "file:photo%0A.png", "file:photo\n.png", "~/photo.png",
                       "file://server/share/photo.png", "file://user@localhost/photo.png",
                       "file://localhost:80/photo.png", "file:///photo.png?query=1", "file:///photo.png#fragment",
                       "ftp://example.com/photo.png", "data:image/png;base64,AAAA", "javascript:photo.png"]
        for target in targets {
            XCTAssertThrowsError(try reference(target).candidates(documentPath: "notes/page.org", document: nil), target)
        }
    }

    func testNetworkURLsPreserveSignedQueriesAndDecodeNoPathTwice() throws {
        let target = "https://example.com/photo%2520one.png?signature=a%2Fb%3D&size=2#preview"
        XCTAssertEqual(try reference(target).candidates(documentPath: "page.org", document: nil), [target])
        XCTAssertEqual(try reference("http://example.com/photo.png").candidates(documentPath: "page.org", document: nil),
                       ["http://example.com/photo.png"])
    }

    func testNetworkURLsWithMixedUnicodeAndEscapesPreserveSignedQueries() throws {
        let target = "https://example.com/图片/猫%20咪.png?signature=a%2Fb%3D&caption=猫%20咪"
        let expected = "https://example.com/%E5%9B%BE%E7%89%87/%E7%8C%AB%20%E5%92%AA.png?signature=a%2Fb%3D&caption=%E7%8C%AB%20%E5%92%AA"
        XCTAssertEqual(try reference(target).candidates(documentPath: "page.org", document: nil), [expected])
        let image = try XCTUnwrap(OrgPreviewImageReference.from(link(target)))
        XCTAssertEqual(image.label, "猫 咪.png")
        let doubleEscaped = "https://example.com/猫%2520咪.png?signature=a%252Fb"
        XCTAssertEqual(try reference(doubleEscaped).candidates(documentPath: "page.org", document: nil),
                       ["https://example.com/%E7%8C%AB%2520%E5%92%AA.png?signature=a%252Fb"])
        XCTAssertEqual(OrgPreviewImageReference.from(link(doubleEscaped))?.label, "猫%20咪.png")
    }

    func testInvalidNetworkHostsCredentialsAndPortsAreRejected() {
        for target in ["https:///photo.png", "https://", "https://user@example.com/photo.png",
                       "https://user:secret@example.com/photo.png", "https://bad host/photo.png",
                       "https://example.com:70000/photo.png", "https://example.com/photo%XX.png",
                       "https://example.com/photo%00.png", "https://example.com/photo%0A.png"] {
            XCTAssertThrowsError(try reference(target).candidates(documentPath: "page.org", document: nil), target)
        }
    }

    func testAttachmentIDUsesWorkspaceAttachThenDocumentLocalData() throws {
        let document = try parse("""
        * Notes
        :PROPERTIES:
        :ID: ab123456
        :END:
        [[attachment:照片/猫%20咪.png]]
        """)
        let image = try XCTUnwrap(references(in: document).first)
        XCTAssertEqual(try image.candidates(documentPath: document.path, document: document),
                       [".attach/ab/123456/照片/猫 咪.png", "notes/data/ab/123456/照片/猫 咪.png"])
    }

    func testAttachmentInheritsParentDIRBeforeConsideringChildID() throws {
        let document = try parse("""
        * Parent
        :PROPERTIES:
        :DIR: ../assets/图片
        :ID: pa1234
        :END:
        ** Child
        :PROPERTIES:
        :ID: ch1234
        :END:
        [[attachment:photo.png]]
        """)
        XCTAssertEqual(try candidates(in: document), [["assets/图片/photo.png"]])
    }

    func testNearestDIRWinsAndSiblingDoesNotInheritPreviousHeading() throws {
        let document = try parse("""
        * Parent
        :PROPERTIES:
        :DIR: parent
        :END:
        ** Child
        :PROPERTIES:
        :DIR: child
        :END:
        [[attachment:one.png]]
        ** Sibling
        [[attachment:two.png]]
        * Other parent
        :PROPERTIES:
        :ID: ot1234
        :END:
        [[attachment:three.png]]
        """)
        XCTAssertEqual(try candidates(in: document), [
            ["notes/child/one.png"], ["notes/parent/two.png"],
            [".attach/ot/1234/three.png", "notes/data/ot/1234/three.png"],
        ])
    }

    func testInheritedIDAndLocalIDChooseCorrectAncestorAtUnicodeOffset() throws {
        let document = try parse("""
        * 家庭🙂
        :PROPERTIES:
        :ID: pa1234
        :END:
        ** 孩子🙂
        [[attachment:one.png]]
        *** 后代
        :PROPERTIES:
        :ID: ch5678
        :END:
        [[attachment:two.png]]
        ** 同级
        [[attachment:three.png]]
        """)
        XCTAssertEqual(try candidates(in: document), [
            [".attach/pa/1234/one.png", "notes/data/pa/1234/one.png"],
            [".attach/ch/5678/two.png", "notes/data/ch/5678/two.png"],
            [".attach/pa/1234/three.png", "notes/data/pa/1234/three.png"],
        ])
    }

    func testFileLevelPropertiesAreInheritedAndLocalDIRCanOverrideThem() throws {
        let document = try parse("""
        :PROPERTIES:
        :DIR: ../shared
        :END:
        [[attachment:first.png]]
        * Child
        :PROPERTIES:
        :ID: ch5678
        :END:
        [[attachment:second.png]]
        * Override
        :PROPERTIES:
        :DIR: own
        :END:
        [[attachment:third.png]]
        """)
        XCTAssertEqual(try candidates(in: document), [
            ["shared/first.png"], ["shared/second.png"], ["notes/own/third.png"],
        ])
    }

    func testAttachmentDIRPreservesLiteralPercentAndAbsolutePaths() throws {
        let literal = try parse("* Heading\n:PROPERTIES:\n:DIR: assets%20raw\n:END:\n[[attachment:a%20b.png]]\n")
        XCTAssertEqual(try candidates(in: literal), [["notes/assets%20raw/a b.png"]])
        let absolute = try parse("* Heading\n:PROPERTIES:\n:DIR: /workspace/图片\n:END:\n[[attachment:a.png]]\n")
        XCTAssertEqual(try candidates(in: absolute), [["/workspace/图片/a.png"]])
        let fileURL = try parse("* Heading\n:PROPERTIES:\n:DIR: file:///workspace/image%20files\n:END:\n[[attachment:a.png]]\n")
        XCTAssertEqual(try candidates(in: fileURL), [["/workspace/image files/a.png"]])
        let root = try parse("* Heading\n:PROPERTIES:\n:DIR: /\n:END:\n[[attachment:a.png]]\n")
        XCTAssertEqual(try candidates(in: root), [["/a.png"]])
    }

    func testAttachmentWithoutPropertiesExplainsMissingLocation() throws {
        let document = try parse("* Empty heading\n[[attachment:photo.png]]\n")
        let image = try XCTUnwrap(references(in: document).first)
        for source in [document, nil] {
            XCTAssertThrowsError(try image.candidates(documentPath: document.path, document: source)) {
                XCTAssertEqual($0 as? OrgPreviewImageReference.Failure, .missingAttachmentDirectory)
            }
        }
    }

    func testAttachmentRejectsInvalidIDsAbsoluteNamesAndEscapingDIR() throws {
        for id in ["a", "ab", "../bad", "ab/cd", "..evil", "ab.."] {
            let document = try parse("* Heading\n:PROPERTIES:\n:ID: \(id)\n:END:\n[[attachment:photo.png]]\n")
            XCTAssertThrowsError(try candidates(in: document), id) {
                XCTAssertEqual($0 as? OrgPreviewImageReference.Failure, .invalidAttachmentID)
            }
        }
        let document = try parse("* Heading\n:PROPERTIES:\n:DIR: ../../outside\n:END:\n[[attachment:photo.png]]\n")
        XCTAssertThrowsError(try candidates(in: document)) {
            XCTAssertEqual($0 as? OrgPreviewImageReference.Failure, .outsideWorkspace)
        }
        for target in ["attachment:/photo.png", "attachment:file:photo.png", "attachment:~/photo.png"] {
            XCTAssertThrowsError(try reference(target).candidates(documentPath: document.path, document: document))
        }
    }

    private func reference(_ target: String) -> OrgPreviewImageReference {
        OrgPreviewImageReference(target: target, label: "Image", startByte: 0)
    }

    private func link(_ target: String, type: String = "link") -> ParsedOrgNode {
        ParsedOrgNode(id: "test", type: type, text: "[[\(target)]]", startByte: 0,
                      endByte: target.utf8.count + 4, children: [
                        ParsedOrgNode(id: "target", type: "link_target", text: target,
                                      startByte: 2, endByte: target.utf8.count + 2, children: [])
                      ])
    }

    private func parse(_ source: String) throws -> ParsedOrgDocument {
        try XCTUnwrap(OrgIndexService.parseSynchronously([
            WorkspaceDocument(path: "notes/page.org", title: "Page", contents: source + "\n", kind: .org)
        ]).first)
    }

    private func references(in document: ParsedOrgDocument) -> [OrgPreviewImageReference] {
        func collect(_ node: ParsedOrgNode) -> [OrgPreviewImageReference] {
            if let image = OrgPreviewImageReference.from(node) { return [image] }
            return node.children.flatMap(collect)
        }
        return collect(document.root)
    }

    private func candidates(in document: ParsedOrgDocument) throws -> [[String]] {
        try references(in: document).map { try $0.candidates(documentPath: document.path, document: document) }
    }
}
