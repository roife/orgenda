import Testing
@testable import OrgTreeSitter

@Test func embeddedNullIsTextRatherThanEndOfFile() throws {
    let source = "* TODO\u{0}Title\n* TODO Next\n"
    let tree = OrgParser().parse(source)
    #expect(!tree.hasError, "\(tree.sExpression)")
    #expect(tree.rootNode.text == source)
    #expect(tree.rootNode.namedChildren.map(\.type) == ["heading", "heading"])
    let heading = try #require(tree.rootNode.namedChildren.first)
    #expect(heading.child(named: "todo") == nil)
    #expect(heading.child(named: "title")?.text == "TODO\u{0}Title")
}

@Test func sourceBlockEndRequiresAnExactDelimiterLine() throws {
    let source = """
      #+BEGIN_SRC text
      #+END_SRC_extra
      #+end_src not-a-delimiter
      literal #+end_src
      #+end_example
      #+END_SRC
    \\(x\\)
    """
    let tree = OrgParser().parse(source)
    #expect(!tree.hasError, "\(tree.sExpression)")
    #expect(tree.rootNode.namedChildren.map(\.type) == ["source_block", "paragraph"])
    let block = try #require(tree.rootNode.namedChildren.first)
    #expect(block.namedChildren.filter { $0.type == "source_line" }.count == 4)
    #expect(block.child(named: "end")?.text == "  #+END_SRC")
}
