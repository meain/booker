// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "booker",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "booker",
            path: "Sources/booker"
        )
    ]
)
