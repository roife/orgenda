# Third-party notices

## tree-sitter

- Project: <https://github.com/tree-sitter/tree-sitter>
- Version: 0.26.3 (`cd4b6e2`)
- License: MIT (`Vendor/tree-sitter/LICENSE`)

The C runtime under `Vendor/tree-sitter` is redistributed and linked into the
Swift package. The Org grammar itself is original to this package and does not
copy the source of `tree-sitter-markdown` or another Org grammar.

The unused `src/wasm` support files are omitted; this package does not enable
`TREE_SITTER_FEATURE_WASM`. The runtime’s disabled-Wasm stubs and Unicode
decoders are retained because native parsing depends on them.
