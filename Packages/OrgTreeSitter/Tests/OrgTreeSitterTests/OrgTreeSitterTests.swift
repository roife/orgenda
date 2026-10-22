import Testing
import Foundation
@testable import OrgTreeSitter

@Test func embeddedNullIsTextRatherThanEndOfFile() throws {
    let source = "* TODO\u{0}Title\n* TODO Next\n"
    let tree = OrgParser().parse(source)
    #expect(!tree.hasError, "\(tree.sExpression)")
    #expect(tree.rootNode.text == source)
    #expect(tree.rootNode.namedChildren.map(\.type) == ["heading", "heading"])
    let heading = try #require(tree.rootNode.namedChildren.first)
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

@Test func incrementalEditsKeepExactSourceBoundariesAndOldSnapshots() {
    let parser = OrgParser()
    let original = "#+TODO: TODO | DONE\r\n* TODO Café 中文🙂\r\nSCHEDULED: <2026-10-22 Thu>\r\n- [ ] first\r\n#+BEGIN_SRC org\r\n* literal\r\n#+END_SRC\r\n$$x$$\r\n* Tail\u{0}\r\n"
    var tree = parser.parse(original)
    let retained = tree.rootNode.namedChildren
    let oldTexts = retained.map(\.text)
    func signature(_ node: OrgSyntaxNode) -> [String] {
        ["\(node.type):\(node.startByte):\(node.endByte):\(node.startPoint.row):\(node.startPoint.column):\(Array(node.text.utf8))"]
            + node.namedChildren.flatMap(signature)
    }
    let revisions = [
        original.replacingOccurrences(of: "Café", with: "Cafe\u{301}"),
        original.replacingOccurrences(of: "🙂", with: "🙃"),
        original.replacingOccurrences(of: "2026-10-22", with: "2026-10-23"),
        original.replacingOccurrences(of: "[ ]", with: "[X]"),
        "前言\n" + original,
        original.replacingOccurrences(of: "#+END_SRC", with: "#+END_SRC_extra"),
        original.replacingOccurrences(of: "$$x$$", with: "$$\nx\n\ny\n$$"),
        "", "中", "文", original,
    ]
    for source in revisions {
        let update = parser.update(source, previous: tree)
        let full = parser.parse(source)
        #expect(signature(update.tree.rootNode) == signature(full.rootNode))
        #expect(Array(update.tree.rootNode.text.utf8) == Array(source.utf8))
        #expect(retained.map(\.text) == oldTexts)
        tree = update.tree
    }
}

@Test func incrementalDeletionAtEveryScalarBoundaryMatchesFreshParse() {
    let parser = OrgParser()
    let source = "* TODO 中文👩🏽‍💻\r\n- [ ] Café\n\\[x\\]\n* Tail\n"
    let original = parser.parse(source)
    let scalars = Array(source.unicodeScalars)
    for index in scalars.indices {
        var changed = scalars
        changed.remove(at: index)
        let text = String(String.UnicodeScalarView(changed))
        let update = parser.update(text, previous: original)
        #expect(update.tree.sExpression == parser.parse(text).sExpression)
        #expect(Array(original.rootNode.text.utf8) == Array(source.utf8))
    }
}

@Test func customBlockBoundariesKeepLiteralHeadingsAndNestedControls() throws {
    let source = "#+begin_note 中文🙂\r\n* Literal\r\n#+BEGIN_note\r\n- [ ] Keep\r\n#+END_note\r\n"
        + "#+END_note_extra\r\n#+END_note trailing\r\n#+END_note\r\n* Tail\r\n"
    let tree = OrgParser().parse(source)
    #expect(!tree.hasIncompleteStructure, "\(tree.sExpression)")
    #expect(tree.rootNode.namedChildren.map(\.type) == ["custom_block", "heading"])
    let outer = try #require(tree.rootNode.namedChildren.first)
    #expect(outer.child(named: "begin")?.text == "#+begin_note 中文🙂")
    #expect(outer.child(named: "end")?.text == "#+END_note")
    let inner = try #require(outer.namedChildren.first { $0.type == "custom_block" })
    let list = try #require(inner.namedChildren.first { $0.type == "list" })
    let checkbox = try #require(list.namedChildren.first?.child(named: "checkbox"))
    #expect(Array(source.utf8)[Int(checkbox.startByte)..<Int(checkbox.endByte)] == ArraySlice("[ ] ".utf8))
    #expect(tree.rootNode.text.utf8.elementsEqual(source.utf8))
}

@Test func incrementalCustomBlockEditsRestoreTheScannerStack() {
    let parser = OrgParser()
    let source = "#+BEGIN_note\n#+BEGIN_inner\n- [ ] 中文🙂\n#+END_inner\n#+END_note\n* Tail\n"
    let original = parser.parse(source)
    func signature(_ node: OrgSyntaxNode) -> [String] {
        ["\(node.type):\(node.startByte):\(node.endByte):\(node.isMissing)"] + node.namedChildren.flatMap(signature)
    }
    let scalars = Array(source.unicodeScalars)
    for index in scalars.indices {
        var changed = scalars
        changed.remove(at: index)
        let text = String(String.UnicodeScalarView(changed))
        let update = parser.update(text, previous: original)
        #expect(signature(update.tree.rootNode) == signature(parser.parse(text).rootNode), "\(text)")
        let restored = parser.update(source, previous: update.tree).tree
        #expect(signature(restored.rootNode) == signature(original.rootNode))
    }
}

@Test func unfinishedDrawerIsVisibleWithoutSwallowingTheNextHeading() {
    let source = "* Task\n:LOGBOOK:\nUnfinished\n* Neighbor\n"
    let tree = OrgParser().parse(source)
    #expect(tree.hasIncompleteStructure)
    #expect(tree.rootNode.namedChildren.filter { $0.type == "heading" }.count == 2)
    #expect(tree.rootNode.text.utf8.elementsEqual(source.utf8))
}
