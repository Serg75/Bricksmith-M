// swift-tools-version:5.7
import PackageDescription

let package = Package(
    // No hyphen, so the generated Obj-C resource accessor finds the shader bundles.
    name: "BricksmithM",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
    ],
    products: [
        .library(name: "LDrawCore", targets: ["LDrawCore"]),
        .library(name: "LDrawRenderCore", targets: ["LDrawRenderCore"]),
        .library(name: "LDrawRenderMetal", targets: ["LDrawRenderMetal"]),
        // macOS only. No other product depends on it, so iOS builds of them never build it.
        .library(name: "LDrawRenderOpenGL", targets: ["LDrawRenderOpenGL"]),
        .library(name: "LDrawEditing", targets: ["LDrawEditing"]),
        .library(name: "LDrawFeatures", targets: ["LDrawFeatures"]),
    ],
    targets: [
        .target(
            name: "LDrawCore",
            path: "Packages/LDrawCore/Sources/LDrawCore",
            publicHeadersPath: "include"
        ),
        .target(
            name: "LDrawRenderCore",
            dependencies: ["LDrawCore"],
            path: "Packages/LDrawRenderCore/Sources/LDrawRenderCore",
            publicHeadersPath: "include"
        ),
        .target(
            name: "LDrawRenderMetal",
            dependencies: ["LDrawCore", "LDrawRenderCore"],
            path: "Packages/LDrawRenderMetal/Sources/LDrawRenderMetal",
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
        .target(
            name: "LDrawRenderOpenGL",
            dependencies: ["LDrawCore", "LDrawRenderCore"],
            path: "Packages/LDrawRenderOpenGL/Sources/LDrawRenderOpenGL",
            resources: [
                .process("Shaders"),
            ],
            publicHeadersPath: "include",
            cSettings: [
                // This package is OpenGL-only, so Apple's OpenGL deprecation warnings are just noise.
                .define("GL_SILENCE_DEPRECATION"),
            ],
            linkerSettings: [
                .linkedFramework("OpenGL", .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "LDrawEditing",
            dependencies: ["LDrawCore", "LDrawRenderCore"],
            path: "Packages/LDrawEditing/Sources/LDrawEditing",
            publicHeadersPath: "include"
        ),
        .target(
            name: "LDrawFeatures",
            dependencies: ["LDrawCore"],
            path: "Packages/LDrawFeatures/Sources/LDrawFeatures",
            publicHeadersPath: "include"
        ),
        .testTarget(
            name: "LDrawCoreTests",
            dependencies: ["LDrawCore"],
            path: "Packages/LDrawCore/Tests/LDrawCoreTests"
        ),
        .testTarget(
            name: "LDrawFeaturesTests",
            dependencies: ["LDrawFeatures", "LDrawCore"],
            path: "Packages/LDrawFeatures/Tests/LDrawFeaturesTests"
        ),
    ]
)
