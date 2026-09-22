import Testing
@testable import OrgTreeSitter

@Test(arguments: [
    ("  ", "  ", "src", "src", "\n"),
    ("\t", "\t", "SrC", "sRc", "\r\n"),
    (" \t", "   ", "SRC", "SRC", "\n"),
    ("", "\t ", "src", "SRC", "\n"),
    ("  ", "", "SRC", "src", "\r\n"),
])
func indentedSourceBlocksEndBeforeFollowingMath(
    _ openingIndent: String,
    _ closingIndent: String,
    _ openingCase: String,
    _ closingCase: String,
    _ newline: String
) throws {
    let opening = "\(openingIndent)#+BeGiN_\(openingCase) verilog :results output"
    let closing = "\(closingIndent)#+EnD_\(closingCase) \t"
    let source = [opening, "  // 中文🙂", "  assign result = 1;", closing,
                  #"\[\alpha\]"#, "* After"].joined(separator: newline) + newline
    let tree = OrgParser().parse(source)
    #expect(!tree.hasError, "\(tree.sExpression)")
    #expect(tree.rootNode.namedChildren.map(\.type) == ["source_block", "paragraph", "heading"])
    let block = try #require(tree.rootNode.namedChildren.first)
    #expect(block.child(named: "begin")?.child(named: "language")?.text == "verilog")
    #expect(block.child(named: "begin")?.child(named: "arguments")?.text == ":results output")
    #expect(block.child(named: "end")?.text == closing)
    #expect(block.namedChildren.filter { $0.type == "source_line" }.count == 2)
    #expect(!block.text.contains(#"\alpha"#))
    #expect(block.endPoint.row == 4)
    #expect(String(decoding: Array(source.utf8)[Int(block.startByte)..<Int(block.endByte)], as: UTF8.self) == block.text)
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

@Test func indentedSourceBlockCanEndAtEOF() throws {
    let source = "\t#+begin_src\ncontent\n \t#+END_SRC"
    let tree = OrgParser().parse(source)
    #expect(!tree.hasError, "\(tree.sExpression)")
    let block = try #require(tree.rootNode.namedChildren.first)
    #expect(block.type == "source_block")
    #expect(block.text == source)
    #expect(block.child(named: "end")?.text == " \t#+END_SRC")
}

@Test func indentedSourceBlockPrefixesRemainText() {
    let source = "  #+BEGIN_SRC_extra\ntext\n  #+END_SRC_extra\n* After\n"
    let tree = OrgParser().parse(source)
    #expect(tree.rootNode.text == source)
    #expect(!tree.rootNode.namedChildren.contains { $0.type == "source_block" })
    #expect(tree.rootNode.namedChildren.last?.type == "heading")
}
