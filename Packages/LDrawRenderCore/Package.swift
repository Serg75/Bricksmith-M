// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "LDrawRenderCore",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
    ],
    products: [
        .library(name: "LDrawRenderCore", targets: ["LDrawRenderCore"]),
    ],
    dependencies: [
        .package(path: "../LDrawCore"),
    ],
    targets: [
        .target(
            name: "LDrawRenderCore",
            dependencies: [
                .product(name: "LDrawCore", package: "LDrawCore"),
            ],
            path: "Sources/LDrawRenderCore",
            publicHeadersPath: "include"
        ),
    ]
)
