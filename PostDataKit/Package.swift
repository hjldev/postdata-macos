// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PostDataKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PostDataKit", targets: ["PostDataKit"]),
    ],
    targets: [
        .target(name: "PostDataKit"),
        .testTarget(
            name: "PostDataKitTests",
            dependencies: ["PostDataKit"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
