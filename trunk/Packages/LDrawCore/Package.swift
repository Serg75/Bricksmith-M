// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "LDrawCore",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
    ],
    products: [
        .library(name: "LDrawCore", targets: ["LDrawCore"]),
    ],
    targets: [
        .target(
            name: "LDrawCore",
            path: "Sources/LDrawCore",
            publicHeadersPath: "include",
            cSettings: [
                .define("WANT_RELATED_PARTS", to: "1"),
                .define("USE_AUTOMATIC_WIREFRAMES", to: "1"),
            ]
        ),
    ]
)
