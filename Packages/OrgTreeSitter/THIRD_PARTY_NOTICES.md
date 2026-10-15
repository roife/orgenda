# Third-party notices

The TreeSitter runtime is resolved by Swift Package Manager from the official
<https://github.com/tree-sitter/tree-sitter> repository at version 0.26.3 (MIT).
Its source is no longer vendored in this package.

The generated parser and external scanner use the local `src/tree_sitter/parser.h`
header from Tree-sitter 0.26.3, licensed under MIT. The license is retained in
`src/tree_sitter/LICENSE`. These parser support headers are independent of the
runtime dependency.

The Org grammar is original to this package and does not copy the source of
`tree-sitter-markdown` or another Org grammar.
