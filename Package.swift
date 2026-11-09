// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ImageOptimMac",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "ImageOptimMac", targets: ["ImageOptimMac"])],
    targets: [
        .target(name: "ImageCore"),
        .executableTarget(name: "ImageOptimMac", dependencies: ["ImageCore"],
                          linkerSettings: [.linkedFramework("AVKit")]),
        .testTarget(name: "ImageCoreTests", dependencies: ["ImageCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "ImageAppTests", dependencies: ["ImageOptimMac", "ImageCore"])
    ]
)
