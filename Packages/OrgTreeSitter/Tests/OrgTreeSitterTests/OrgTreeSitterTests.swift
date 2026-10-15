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

@Test func mathDelimitersTakePrecedenceOverOrgMarkup() {
    let formulas = [#"\(a=b\)"#, "$x=y$", #"\(z=1\)"#, "$bb$s", #"$x \gets $"#]
    let source = "中文 " + formulas.joined(separator: " then ") + " =literal= ~code~\n"
    let tree = OrgParser().parse(source)
    #expect(!tree.hasError, "\(tree.sExpression)")
    let nodes = mathNodes(in: tree.rootNode)
    #expect(nodes.map(\.text) == formulas.map { $0 == "$bb$s" ? "$bb$" : $0 })
    #expect(nodes.allSatisfy { $0.type == "latex_fragment" })
    for node in nodes {
        let bytes = Array(source.utf8)[Int(node.startByte)..<Int(node.endByte)]
        #expect(String(decoding: bytes, as: UTF8.self) == node.text)
    }
    let children = tree.rootNode.namedChildren.first?.namedChildren ?? []
    #expect(children.contains { $0.type == "verbatim" && $0.text == "=literal=" })
    #expect(children.contains { $0.type == "code" && $0.text == "~code~" })
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

@Test(arguments: [
    "equation", "equation*", "displaymath", "align", "align*", "aligned", "alignat", "alignat*", "alignedat",
    "gather", "gather*", "multline", "multline*", "eqnarray", "eqnarray*", "cases", "array", "matrix",
    "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix",
]) func mathEnvironmentWhitelist(name: String) {
    let formula = "\\begin{\(name)}x\\end{\(name)}"
    let tree = OrgParser().parse(formula + "\n")
    #expect(!tree.hasError, "\(tree.sExpression)")
    #expect(mathNodes(in: tree.rootNode).map(\.text) == [formula])
}

@Test func mathIsRecognizedInTablesAndContainers() throws {
    let source = #"""
    | $a=b$ | \(x|y\) |
    #+begin_quote
    before
    \[
    a=b

    c=d
    \]
    after
    #+end_quote
    :MATH:
    $$x=y$$
    :END:
    #+begin_verse
    \begin{equation}a=b\end{equation}
    #+end_verse
    #+begin_center
    $$x$$
    #+end_center
    #+begin: math
    $$y$$
    #+end:
    """#
    let tree = OrgParser().parse(source)
    #expect(!tree.hasError, "\(tree.sExpression)")
    #expect(mathNodes(in: tree.rootNode).count == 7)
    for type in ["quote_block", "drawer", "verse_block", "center_block", "dynamic_block"] {
        let container = try #require(tree.rootNode.namedChildren.first { $0.type == type })
        #expect(container.namedChildren.contains { $0.type == "latex_block" }, "\(container.sExpression)")
    }
}

@Test func literalAndEscapedMathStaysText() {
    let source = #"""
    =\(literal\)= ~$code$~ [[https://example.org/$path$][link]]
    \$escaped$ \\(escaped\\) word$x$ 中文$x$ $5 and $6
    #+begin_src latex
    \(x\)
    $$y$$
    #+end_src
    #+begin_example
    $$z$$
    #+end_example
    #+begin_export latex
    $$z$$
    #+end_export
    #+begin_comment
    $$z$$
    #+end_comment
    """#
    let tree = OrgParser().parse(source)
    #expect(!tree.hasError, "\(tree.sExpression)")
    #expect(mathNodes(in: tree.rootNode).isEmpty)
}

@Test(arguments: ["$$", "$$x", #"\["#, #"\[x"#, #"\("#, #"\(x"#, "$x", #"\begin{align}x\end{gather}"#, #"\begin{unknown}x\end{unknown}"#])
func incompleteOrUnknownMathRemainsEditable(formula: String) {
    let source = formula + "\n* TODO Tail\n"
    let tree = OrgParser().parse(source)
    #expect(!tree.hasError, "\(tree.sExpression)")
    #expect(mathNodes(in: tree.rootNode).isEmpty)
    #expect(tree.rootNode.namedChildren.last?.type == "heading")
}

@Test func explicitInlineMathMaySpanBlankLines() {
    let formula = "\\(x=1\n\ny=2\\)"
    let tree = OrgParser().parse(formula + "\n")
    #expect(!tree.hasError, "\(tree.sExpression)")
    #expect(mathNodes(in: tree.rootNode).map(\.text) == [formula])
}

@Test func punctuationCanIntroduceDollarMath() {
    let tree = OrgParser().parse("中文，$x$; $y$ and word$literal$ and $z$.\n")
    #expect(!tree.hasError, "\(tree.sExpression)")
    #expect(mathNodes(in: tree.rootNode).map(\.text) == ["$x$", "$y$", "$z$"])
}
