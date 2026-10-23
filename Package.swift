// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RemioCore",
    platforms: [.macOS(.v15), .iOS("26.0")],
    products: [.library(name: "RemioCore", targets: ["RemioCore"])],
    targets: [
        .target(name: "RemioCore", path: "ios/Remio",
                exclude: ["App", "Core/Design", "Resources", "Features/Connection", "Features/Settings",
                          "Features/Remote/RemoteView.swift", "Features/Remote/TrackpadView.swift",
                          "Features/Administration", "Features/Remote/NativeRemoteKeyboard.swift"],
                sources: ["Core/Portal", "Core/ADB", "Features/Remote/RemoteModel.swift"]),
        .testTarget(name: "RemioCoreTests", dependencies: ["RemioCore"], path: "tests/RemioCoreTests")
    ]
)
