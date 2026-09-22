// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OrgTreeSitter",
    platforms: [.iOS("27.0"), .macOS(.v14)],
    products: [
        .library(name: "OrgTreeSitter", targets: ["OrgTreeSitter"]),
    ],
    targets: [
        .target(
            name: "CTreeSitter",
            path: "Vendor/tree-sitter",
            sources: ["src/lib.c"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("src")]
        ),
        .target(
            name: "COrgTreeSitter",
            dependencies: ["CTreeSitter"],
            path: "src",
            sources: ["parser.c", "scanner.c"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath(".")]
        ),
        .target(
            name: "OrgTreeSitter",
            dependencies: ["CTreeSitter", "COrgTreeSitter"]
        ),
        .testTarget(name: "OrgTreeSitterTests", dependencies: ["OrgTreeSitter"]),
    ]
)
