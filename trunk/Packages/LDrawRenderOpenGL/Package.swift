// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "LDrawRenderOpenGL",
    platforms: [
        .macOS(.v11),
    ],
    products: [
        .library(name: "LDrawRenderOpenGL", targets: ["LDrawRenderOpenGL"]),
    ],
    dependencies: [
        .package(path: "../LDrawCore"),
        .package(path: "../LDrawRenderCore"),
    ],
    targets: [
        .target(
            name: "LDrawRenderOpenGL",
            dependencies: [
                .product(name: "LDrawCore", package: "LDrawCore"),
                .product(name: "LDrawRenderCore", package: "LDrawRenderCore"),
            ],
            path: "Sources/LDrawRenderOpenGL",
            resources: [
                .process("Shaders"),
            ],
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("OpenGL"),
            ]
        ),
    ]
)
