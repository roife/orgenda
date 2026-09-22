import Testing
@testable import OrgTreeSitter

@Test func parsesRepresentativeOrgDocument() {
    let source = """
    * TODO [#A] Build parser :ios:parser:project:
    SCHEDULED: <2026-08-30 Sun 10:00>
    :PROPERTIES:
    :ID: parser-001
    :END:
    - [ ] Parse *markup* and [[id:target][links]]
    """

    let tree = OrgParser().parse(source)

    #expect(!tree.hasError)
    #expect(tree.rootNode.type == "document")
    #expect(tree.rootNode.namedChildren.map(\.type) == [
        "heading", "planning", "property_drawer", "list",
    ])
    #expect(tree.sExpression.contains("(todo_keyword)"))
    #expect(tree.sExpression.contains("(link"))
}

@Test func exposesFieldsTextAndLocations() throws {
    let tree = OrgParser().parse("* WAIT Call Alice :phone:\n")
    let heading = try #require(tree.rootNode.namedChildren.first)
    let title = try #require(heading.child(named: "title"))
    let todo = try #require(heading.child(named: "todo"))

    #expect(todo.text == "WAIT ")
    #expect(title.text == "Call Alice ")
    #expect(heading.startPoint == OrgPoint(row: 0, column: 0))
    #expect(heading.endPoint == OrgPoint(row: 1, column: 0))
}

@Test func exposesBundledLanguageABI() {
    #expect(OrgTreeSitter.abiVersion > 0)
}

@Test(arguments: [
    "https://example.com/path/to/page",
    "http://example.com/a_b/c_d?q=one+two&next=/docs/#section",
    "https://example.com/",
    "HTTPS://example.com/path",
    "https://example.com/wiki/Topic_(detail)",
    "mailto:first_last@example.com",
    "ftp://example.com/pub/files",
])
func parsesPlainLinksWithoutEmphasis(_ target: String) throws {
    let source = "\(target) /italic/\n"
    let tree = OrgParser().parse(source)
    #expect(!tree.hasError, "\(tree.sExpression)")
    let paragraph = try #require(tree.rootNode.namedChildren.first)
    #expect(paragraph.namedChildren.map(\.type) == ["plain_link", "whitespace", "italic"])
    #expect(paragraph.namedChildren.first?.text == target)
    #expect(paragraph.namedChildren.last?.text == "/italic/")
    #expect(tree.rootNode.text == source)
}

@Test(arguments: [
    "https://example.com/path.",
    "(https://example.com/path)",
    "\"https://example.com/path\"",
    "https://example.com/path,",
    "https://example.com/path;",
    "https://example.com/path!",
    "https://example.com/path?",
])
func plainLinksExcludeSurroundingPunctuation(_ source: String) throws {
    let tree = OrgParser().parse(source)
    #expect(!tree.hasError, "\(tree.sExpression)")
    let paragraph = try #require(tree.rootNode.namedChildren.first)
    let link = try #require(paragraph.namedChildren.first { $0.type == "plain_link" })
    #expect(link.text == "https://example.com/path")
    #expect(!tree.sExpression.contains("(italic)"))
    #expect(tree.rootNode.text == source)
}

@Test func linksRemainAtomicInEveryInlineContext() {
    let source = """
    * TODO https://example.com/a/b /italic/
    - https://example.com/a/b /italic/
    |https://example.com/a/b|/italic/|
    [[https://example.com/a/b][Label /literal/]]
    <https://example.com/a/b>
    ~https://example.com/a/b~ =https://example.com/a/b=
    """
    let tree = OrgParser().parse(source)
    #expect(!tree.hasError, "\(tree.sExpression)")
    func descendants(_ node: OrgSyntaxNode) -> [OrgSyntaxNode] {
        [node] + node.namedChildren.flatMap(descendants)
    }
    let nodes = descendants(tree.rootNode)
    #expect(nodes.filter { $0.type == "plain_link" }.map(\.text) == Array(repeating: "https://example.com/a/b", count: 3))
    #expect(nodes.filter { $0.type == "italic" }.map(\.text) == Array(repeating: "/italic/", count: 3))
    #expect(nodes.filter { $0.type == "link" }.count == 1)
    #expect(nodes.filter { $0.type == "angle_link" }.count == 1)
    #expect(nodes.filter { $0.type == "code" }.map(\.text) == ["~https://example.com/a/b~"])
    #expect(nodes.filter { $0.type == "verbatim" }.map(\.text) == ["=https://example.com/a/b="])
}

@Test func doesNotTreatAnUppercaseTitleAsAWorkflowState() throws {
    let tree = OrgParser().parse("* API Design notes\n")
    let heading = try #require(tree.rootNode.namedChildren.first)

    #expect(heading.child(named: "todo") == nil)
    #expect(heading.child(named: "title")?.text == "API Design notes")
}

@Test func parsesDrawersAndClocksWithExactUnicodeRanges() throws {
    let source = "* TODO 工作🙂\r\n  :logbook:\r\n  CLOCK: [2026-09-19 Sat 09:00]--[2026-09-19 Sat 10:25] =>  1:25\r\n  - State \"DONE\" from \"TODO\" [2026-09-19 Sat]\r\n  :eNd:\r\n正文\r\n:NOTES-extra:\r\n*bold*\r\n:END:"
    let tree = OrgParser().parse(source)
    #expect(!tree.hasError, "\(tree.sExpression)")
    #expect(tree.rootNode.namedChildren.map(\.type) == ["heading", "drawer", "paragraph", "drawer"])
    let drawer = try #require(tree.rootNode.namedChildren.first { $0.type == "drawer" })
    #expect(drawer.child(named: "begin")?.text == "  :logbook:")
    #expect(drawer.child(named: "end")?.text == "  :eNd:")
    #expect(drawer.namedChildren.map(\.type) == ["drawer_begin", "clock", "list", "drawer_end"])
    let clock = try #require(drawer.namedChildren.first { $0.type == "clock" })
    #expect(clock.child(named: "duration")?.text == "=>  1:25")
    #expect(clock.child(named: "end")?.text == "[2026-09-19 Sat 10:25]")
    #expect(String(decoding: Array(source.utf8)[Int(drawer.startByte)..<Int(drawer.endByte)], as: UTF8.self) == drawer.text)
}

@Test(arguments: [
    ":LOGBOOK:\nunfinished\n* TODO Visible\n:END:\n",
    ":LOGBOOK:\nunfinished",
    ":END:\n* TODO Visible\n",
    "Text :LOGBOOK:\nnot a drawer\n:END:\n",
]) func incompleteOrInlineDrawersRemainText(_ source: String) {
    let tree = OrgParser().parse(source)
    #expect(!tree.hasError, "\(tree.sExpression)")
    #expect(!tree.rootNode.namedChildren.contains { $0.type == "drawer" })
    if source.contains("* TODO") {
        #expect(tree.rootNode.namedChildren.contains { $0.type == "heading" })
    }
}

@Test func drawersCannotNest() {
    let tree = OrgParser().parse(":OUTER:\n:INNER:\ntext\n:END:\n:END:\n")
    #expect(!tree.hasError)
    #expect(tree.rootNode.namedChildren.first?.type == "paragraph")
    #expect(tree.rootNode.namedChildren.filter { $0.type == "drawer" }.count == 1)
}

@Test func parsesIndentedPropertiesAndStandaloneClocks() {
    let tree = OrgParser().parse("* TODO Work\n  :properties:\n  :ID: abc\n  :HEADER-ARGS+: :results output\n  :end:\nclock: [2026-09-19]\nCLOCK: => 12:30\n")
    #expect(!tree.hasError, "\(tree.sExpression)")
    #expect(tree.rootNode.namedChildren.map(\.type) == ["heading", "property_drawer", "clock", "clock"])
}

@Test(arguments: ["example", "export", "comment", "verse", "center"])
func parsesAdditionalDelimitedBlocks(_ name: String) throws {
    let source = "  #+BeGiN_\(name) parameters\n*bold* [25%]\n  #+EnD_\(name)\n* TODO Outside\n"
    let tree = OrgParser().parse(source)
    #expect(!tree.hasError, "\(tree.sExpression)")
    #expect(tree.rootNode.namedChildren.map(\.type) == ["\(name)_block", "heading"])
    let block = try #require(tree.rootNode.namedChildren.first)
    if ["example", "export", "comment"].contains(name) {
        #expect(!block.sExpression.contains("(bold)"))
        #expect(block.sExpression.contains("(source_content)"))
    } else {
        #expect(block.sExpression.contains("(bold)"))
        #expect(block.sExpression.contains("(statistics_cookie)"))
    }
}

@Test func parsesDynamicBlocksAndFixedWidth() {
    let source = "#+BEGIN: clocktable :scope file\n| Task | Time |\n#+END:\n: literal *bold*\n:\n  : more\n-----\n* TODO Outside\n"
    let tree = OrgParser().parse(source)
    #expect(!tree.hasError, "\(tree.sExpression)")
    #expect(tree.rootNode.namedChildren.map(\.type) == ["dynamic_block", "fixed_width", "horizontal_rule", "heading"])
    #expect(!tree.sExpression.contains("(bold)"))
}

@Test func parsesExtendedObjectsInHeadingsListsAndTables() {
    let source = "* TODO [#27] Progress [2/3] [50%]\n- [@3] [X] Term :: definition\nSee <<target>> <<<radio>>> {{{title}}} @@html:<b>x</b>@@ <https://orgmode.org> [fn::note].\n| [1/2] | {{{name(arg)}}} | @literal {braces} |\n"
    let tree = OrgParser().parse(source)
    #expect(!tree.hasError, "\(tree.sExpression)")
    for type in ["priority", "statistics_cookie", "list_counter", "checkbox", "description_tag", "target", "radio_target", "macro", "export_snippet", "angle_link", "inline_footnote"] {
        #expect(tree.sExpression.contains("(\(type))"), "Missing \(type): \(tree.sExpression)")
    }
}

@Test func delimiterPrefixesRemainOrdinaryText() {
    let tree = OrgParser().parse("-----ordinary text\n#+BEGIN_EXAMPLE_extra\nnormal\n#+END_EXAMPLE_extra\n* Heading\n")
    #expect(!tree.hasError, "\(tree.sExpression)")
    #expect(tree.rootNode.namedChildren.map(\.type) == ["paragraph", "paragraph", "paragraph", "paragraph", "heading"])
}

@Test func emptyDrawersAndLiteralLinesDoNotLoseNewlines() {
    for newline in ["\n", "\r\n"] {
        for suffix in ["", newline] {
            let source = ":LOGBOOK:\(newline):END:\(newline):\(newline): text\(suffix)"
            let tree = OrgParser().parse(source)
            #expect(!tree.hasError, "\(tree.sExpression)")
            #expect(tree.rootNode.namedChildren.map(\.type) == ["drawer", "fixed_width"])
            #expect(tree.rootNode.namedChildren.map(\.text).joined() == source)
        }
    }
}
