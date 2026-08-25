// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "LDrawEditing",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
    ],
    products: [
        .library(name: "LDrawEditing", targets: ["LDrawEditing"]),
    ],
    dependencies: [
        .package(path: "../LDrawCore"),
        .package(path: "../LDrawRenderCore"),
    ],
    targets: [
        .target(
            name: "LDrawEditing",
            dependencies: [
                .product(name: "LDrawCore", package: "LDrawCore"),
                .product(name: "LDrawRenderCore", package: "LDrawRenderCore"),
            ],
            path: "Sources/LDrawEditing",
            publicHeadersPath: "include"
        ),
    ]
)
