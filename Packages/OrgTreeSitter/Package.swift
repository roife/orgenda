// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OrgTreeSitter",
    platforms: [.iOS("27.0"), .macOS(.v14)],
    products: [
        .library(name: "OrgTreeSitter", targets: ["OrgTreeSitter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/tree-sitter", exact: "0.26.3"),
    ],
    targets: [
        .target(
            name: "COrgTreeSitter",
            dependencies: [.product(name: "TreeSitter", package: "tree-sitter")],
            path: "src",
            sources: ["parser.c", "scanner.c"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath(".")]
        ),
        .target(
            name: "OrgTreeSitter",
            dependencies: [.product(name: "TreeSitter", package: "tree-sitter"), "COrgTreeSitter"]
        ),
        .testTarget(name: "OrgTreeSitterTests", dependencies: ["OrgTreeSitter"]),
    ]
)
