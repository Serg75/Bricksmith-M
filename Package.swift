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
        // What a host draws of a step: its callouts and the labels of its parts list. No editing.
        .library(name: "LDrawStepRendering", targets: ["LDrawStepRendering"]),
        // What a host that edits callouts adds to that.
        .library(name: "LDrawStepEditing", targets: ["LDrawStepEditing"]),
        .library(name: "LDrawConnectivity", targets: ["LDrawConnectivity"]),
        // Inventories, part availability, and the parts limit built from them. No network.
        .library(name: "LDrawInventory", targets: ["LDrawInventory"]),
        // Rebrickable's downloads, read into LDrawInventory's types. The only network code.
        .library(name: "LDrawRebrickable", targets: ["LDrawRebrickable"]),
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
            dependencies: ["LDrawCore", "LDrawInventory"],
            path: "Packages/LDrawFeatures/Sources/LDrawFeatures",
            publicHeadersPath: "include"
        ),
        .target(
            name: "LDrawStepRendering",
            dependencies: ["LDrawCore", "LDrawFeatures"],
            path: "Packages/LDrawStepRendering/Sources/LDrawStepRendering",
            publicHeadersPath: "include"
        ),
        .target(
            name: "LDrawStepEditing",
            dependencies: ["LDrawCore", "LDrawFeatures"],
            path: "Packages/LDrawStepEditing/Sources/LDrawStepEditing",
            publicHeadersPath: "include"
        ),
        .target(
            name: "LDrawConnectivity",
            dependencies: ["LDrawCore"],
            path: "Packages/LDrawConnectivity/Sources/LDrawConnectivity",
            publicHeadersPath: "include"
        ),
        .target(
            name: "LDrawInventory",
            dependencies: ["LDrawCore"],
            path: "Packages/LDrawInventory/Sources/LDrawInventory",
            publicHeadersPath: "include"
        ),
        .target(
            name: "LDrawRebrickable",
            dependencies: ["LDrawInventory", "LDrawCore"],
            path: "Packages/LDrawRebrickable/Sources/LDrawRebrickable",
            resources: [
                .process("Resources"),
            ],
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("z"),
            ]
        ),
        // Helpers for the test targets. No product uses it.
        .target(
            name: "LDrawTestSupport",
            path: "Packages/LDrawTestSupport/Sources/LDrawTestSupport"
        ),
        .testTarget(
            name: "LDrawCoreTests",
            dependencies: ["LDrawCore"],
            path: "Packages/LDrawCore/Tests/LDrawCoreTests"
        ),
        .testTarget(
            name: "LDrawFeaturesTests",
            dependencies: ["LDrawFeatures", "LDrawCore", "LDrawInventory", "LDrawTestSupport"],
            path: "Packages/LDrawFeatures/Tests/LDrawFeaturesTests"
        ),
        .testTarget(
            name: "LDrawStepRenderingTests",
            dependencies: ["LDrawStepRendering", "LDrawStepEditing", "LDrawFeatures", "LDrawCore", "LDrawTestSupport"],
            path: "Packages/LDrawStepRendering/Tests/LDrawStepRenderingTests"
        ),
        .testTarget(
            name: "LDrawStepEditingTests",
            dependencies: ["LDrawStepEditing", "LDrawFeatures", "LDrawCore", "LDrawTestSupport"],
            path: "Packages/LDrawStepEditing/Tests/LDrawStepEditingTests"
        ),
        .testTarget(
            name: "LDrawInventoryTests",
            dependencies: ["LDrawInventory", "LDrawCore"],
            path: "Packages/LDrawInventory/Tests/LDrawInventoryTests"
        ),
        .testTarget(
            name: "LDrawRebrickableTests",
            dependencies: ["LDrawRebrickable", "LDrawInventory", "LDrawCore"],
            path: "Packages/LDrawRebrickable/Tests/LDrawRebrickableTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
        .testTarget(
            name: "LDrawConnectivityTests",
            dependencies: ["LDrawConnectivity", "LDrawCore"],
            path: "Packages/LDrawConnectivity/Tests/LDrawConnectivityTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
