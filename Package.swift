// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MicMuteBar",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "MicMuteBar"
        ),
    ]
)
