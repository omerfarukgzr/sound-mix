// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TabMixer",
    platforms: [.macOS("14.4")],
    targets: [
        .executableTarget(name: "TabMixer", path: "Sources/TabMixer")
    ]
)
