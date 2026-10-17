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

private func mathNodes(in node: OrgSyntaxNode) -> [OrgSyntaxNode] {
    if node.type == "latex_block" || node.type == "latex_fragment" { return [node] }
    return node.namedChildren.flatMap { mathNodes(in: $0) }
}

@Test func displayMathSpansBlankLinesAndKeepsMatchingNestedEnvironments() {
    let formulas = [
        "$$\nx=1\n\ny=2\n$$",
        "\\[\r\nx=1\r\n\r\ny=2\r\n\\]",
        #"\begin{align}a &= b"# + "\n\n" + #"\begin{align}c &= d\end{align}\end{matrix}e &= f\end{align}"#,
    ]
    let source = formulas.joined(separator: "\n") + "\n* TODO Tail\n"
    let tree = OrgParser().parse(source)
    #expect(!tree.hasError, "\(tree.sExpression)")
    #expect(mathNodes(in: tree.rootNode).map(\.text) == formulas)
    #expect(tree.rootNode.namedChildren.filter { $0.type == "latex_block" }.count == 3)
    #expect(tree.rootNode.namedChildren.last?.type == "heading")
}

@Test(arguments: ["$$", "$$x", #"\["#, #"\[x"#, #"\("#, #"\(x"#, "$x", #"\begin{align}x\end{gather}"#, #"\begin{unknown}x\end{unknown}"#])
func incompleteOrUnknownMathRemainsEditable(formula: String) {
    let source = formula + "\n* TODO Tail\n"
    let tree = OrgParser().parse(source)
    #expect(!tree.hasError, "\(tree.sExpression)")
    #expect(mathNodes(in: tree.rootNode).isEmpty)
    #expect(tree.rootNode.namedChildren.last?.type == "heading")
}
