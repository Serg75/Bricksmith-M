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
            cSettings: [
                // This package is OpenGL-only, so Apple's OpenGL deprecation warnings are just noise.
                .define("GL_SILENCE_DEPRECATION"),
            ],
            linkerSettings: [
                .linkedFramework("OpenGL"),
            ]
        ),
    ]
)
