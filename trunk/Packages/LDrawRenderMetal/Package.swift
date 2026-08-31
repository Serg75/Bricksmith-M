// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "LDrawRenderMetal",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
    ],
    products: [
        .library(name: "LDrawRenderMetal", targets: ["LDrawRenderMetal"]),
    ],
    dependencies: [
        .package(path: "../LDrawCore"),
        .package(path: "../LDrawRenderCore"),
    ],
    targets: [
        .target(
            name: "LDrawRenderMetal",
            dependencies: [
                .product(name: "LDrawCore", package: "LDrawCore"),
                .product(name: "LDrawRenderCore", package: "LDrawRenderCore"),
            ],
            path: "Sources/LDrawRenderMetal",
            resources: [
                .process("Shaders"),
            ],
            publicHeadersPath: "include",
            cSettings: [
                .define("METAL"),
            ],
            linkerSettings: [
                .linkedFramework("MetalKit"),
            ]
        ),
    ]
)
